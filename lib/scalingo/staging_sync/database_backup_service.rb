# frozen_string_literal: true

require "scalingo"
require "net/http"
require "fileutils"

module Scalingo
  module StagingSync
    class DatabaseBackupService
      class BackupError < StandardError
      end

      class AddonNotFoundError < BackupError
      end

      class BackupNotFoundError < BackupError
      end

      class DownloadError < BackupError
      end

      DEFAULT_TIMEOUT = 1200 # 20 minutes
      DEFAULT_MAX_RETRIES = 3
      DEFAULT_RETRY_DELAY = 5 # seconds

      def initialize(source_app, temp_dir, logger: Rails.logger, options: {})
        @source_app = source_app
        @temp_dir = temp_dir
        @logger = logger
        @timeout = options[:timeout] || DEFAULT_TIMEOUT
        @max_retries = options[:max_retries] || DEFAULT_MAX_RETRIES
        @retry_delay = options[:retry_delay] || DEFAULT_RETRY_DELAY
        @slack_notifier = Scalingo::StagingSync::SlackNotificationService.new(logger: logger)
        @client = initialize_scalingo_client
        FileUtils.mkdir_p(@temp_dir)
      end

      def download_and_extract!(force_download: false)
        # Check for force download from ENV variable or keyword argument
        force = force_download || ENV["FORCE_BACKUP_DOWNLOAD"].to_s.downcase == "true"

        log_context(:info, "Starting download_and_extract process", app: @source_app, force_download: force)
        @slack_notifier.backup_step("📦 Téléchargement de la sauvegarde depuis #{@source_app}...")

        Dir.chdir(@temp_dir) do
          # Check if archive already exists
          log_context(:info, "Checking for existing archives in #{@temp_dir}")
          archive = find_latest_archive

          if archive && !force
            log_context(
              :info,
              "Found existing archive, skipping download",
              archive: archive,
              size: format_bytes(File.size(archive))
            )
            @slack_notifier.backup_step("🔄 Utilisation de l'archive existante: #{File.basename(archive)}")
          else
            if archive && force
              log_context(
                :info,
                "Found existing archive but forcing redownload",
                archive: archive,
                reason: force_download ? "force_download argument" : "FORCE_BACKUP_DOWNLOAD env"
              )

              # Remove the existing archive before downloading new one
              FileUtils.rm_f(archive)
              log_context(:info, "Removed existing archive", archive: archive)
            end

            # Download the latest backup using HTTP API
            log_context(:info, "Initiating backup download via Scalingo API", app: @source_app, forced: force)
            @slack_notifier.backup_step("📡 Récupération de la dernière sauvegarde...")

            archive = with_retry { download_backup_via_api }
            raise DownloadError, "Failed to download backup from #{@source_app}" unless archive

            log_context(:info, "Backup download completed", archive: archive, size: format_bytes(File.size(archive)))
          end

          result = extract_and_prepare_backup(archive)
          log_context(:info, "Download and extraction completed successfully", final_path: result.to_s)
          @slack_notifier.backup_step("✅ Sauvegarde prête")
          result
        end
      rescue StandardError => e
        log_context(
          :error,
          "Backup processing failed",
          error: e.message,
          app: @source_app,
          backtrace: e.backtrace.first(3).join(" | ")
        )
        @slack_notifier.backup_error("Échec du téléchargement")
        raise
      end

      def extract_and_prepare_backup(archive)
        log_context(:info, "Starting archive extraction", archive: archive, size: format_bytes(File.size(archive)))
        @slack_notifier.backup_step("📦 Extraction de l'archive...")

        log_context(:info, "Running tar extraction command")
        success = system("tar -xzf \"#{archive}\"")
        raise BackupError, "Failed to extract archive: #{archive}" unless success

        log_context(:info, "Archive extraction completed successfully")

        # Find the dump file
        log_context(:info, "Searching for dump file in extracted contents")
        dump_file = find_dump_file
        raise BackupError, "No dump file found in archive" unless dump_file

        log_context(:info, "Found dump file", dump_file: dump_file, size: format_bytes(File.size(dump_file)))

        # Standardize the filename
        standardized_path = @temp_dir.join("production.dump")
        log_context(:info, "Standardizing dump filename", from: dump_file, to: standardized_path.to_s)
        FileUtils.mv(dump_file, standardized_path)

        log_context(:info, "Cleaning up archive file", archive: archive)
        FileUtils.rm_f(archive)

        log_context(
          :info,
          "Backup preparation completed",
          path: standardized_path.to_s,
          size: format_bytes(File.size(standardized_path))
        )
        standardized_path
      end

      private

      def initialize_scalingo_client
        log_context(:info, "Initializing Scalingo client")
        token = ENV.fetch("SCALINGO_API_TOKEN") do
          raise BackupError, "SCALINGO_API_TOKEN environment variable not set"
        end

        client = Scalingo::Client.new
        client.authenticate_with(access_token: token)
        log_context(:info, "Scalingo client authenticated successfully")
        client
      rescue StandardError => e
        log_context(:error, "Failed to initialize Scalingo client", error: e.message)
        @slack_notifier.backup_error("Échec connexion Scalingo")
        raise
      end

      def download_backup_via_api
        # Step 1: Get app addons to find the PostgreSQL addon
        log_context(:info, "Step 1: Fetching PostgreSQL addon for app", app: @source_app)
        addon_id = get_postgresql_addon_id

        # Step 2: Get database client for the addon
        log_context(:info, "Step 2: Getting database client for addon", addon_id: addon_id)
        db_client = get_database_client(addon_id)

        # Step 3: Get the latest backup
        log_context(:info, "Step 3: Fetching latest backup information", addon_id: addon_id)
        backup_info = get_latest_backup(db_client, addon_id)

        # Step 4: Get download URL for the backup
        # Following the pattern from ScalingoBackupsManager::Backup#download_link
        log_context(
          :info,
          "Step 4: Requesting download URL for backup",
          backup_id: backup_info[:id],
          addon_id:  addon_id
        )

        database_api_url = "https://db-api.osc-fr1.scalingo.com/api/databases/#{addon_id}"
        archive_url = "#{database_api_url}/backups/#{backup_info[:id]}/archive"

        log_context(:debug, "Making archive request", url: archive_url)

        archive_response = with_retry { db_client.authenticated_connection.get(archive_url).body }

        log_context(
          :info,
          "Archive response received",
          response_keys: archive_response.keys.join(", "),
          has_download_url: archive_response.key?(:download_url)
        )

        # Step 5: Download the backup file
        download_url = archive_response[:download_url]

        unless download_url
          log_context(:error, "No download URL in response", response: archive_response.inspect)
          raise DownloadError, "No download URL received"
        end

        log_context(
          :info,
          "Step 5: Download URL obtained",
          url_length: download_url.length,
          url_host: URI(download_url).host
        )

        filename = "backup-" + Time.zone.now.strftime("%Y%m%d-%H%M%S") + ".tar.gz"

        log_context(
          :info,
          "Starting backup download",
          filename: filename,
          source_app: @source_app,
          addon_id:   addon_id
        )

        download_file(download_url, filename)

        log_context(:info, "Backup download process completed", filename: filename, app: @source_app)
        filename
      end

      def get_database_client(addon_id)
        # Following the pattern from ScalingoBackupsManager::Addon#client
        # Get addon token for authentication
        response = with_retry { @client.osc_fr1.addons.token(@source_app, addon_id) }

        bearer_token = response.data&.dig(:token)
        raise BackupError, "Failed to authenticate with addon" unless bearer_token

        # Create database API client with authenticated connection
        database_api_url = "https://db-api.osc-fr1.scalingo.com/api/databases/#{addon_id}"

        addon_config = Scalingo::Client.new
        addon_config.token = bearer_token

        Scalingo::API::Client.new(database_api_url, scalingo: addon_config)
      end

      def get_postgresql_addon_id
        # Using the pattern from ScalingoBackupsManager::Addon.find
        addons = with_retry { @client.osc_fr1.addons.for(@source_app) }
        pg_addon = addons.data.find { |addon| addon[:addon_provider][:id] == "postgresql" }

        raise AddonNotFoundError, "No PostgreSQL addon found for app #{@source_app}" unless pg_addon

        log_context(:info, "Found PostgreSQL addon", addon_id: pg_addon[:id], app: @source_app)
        pg_addon[:id]
      end

      def get_latest_backup(db_client, addon_id)
        # Following the pattern from ScalingoBackupsManager::Addon#backups
        database_api_url = "https://db-api.osc-fr1.scalingo.com/api/databases/#{addon_id}"

        response = with_retry { db_client.authenticated_connection.get("#{database_api_url}/backups").body }

        backups = response[:database_backups] || []
        raise BackupNotFoundError, "No backups found for addon #{addon_id}" if backups.empty?

        # Get the most recent backup (they use first, but we'll use most recent by date)
        latest = backups.max_by { |b| Time.zone.parse(b[:created_at]) }

        log_context(
          :info,
          "Found latest backup",
          backup_id: latest[:id],
          created_at: latest[:created_at],
          addon_id: addon_id
        )
        latest
      end

      def download_file(url, filename)
        uri = URI(url)
        bytes_downloaded = 0
        start_time = Time.zone.now

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.read_timeout = @timeout
        http.open_timeout = 30

        request = Net::HTTP::Get.new(uri)

        File.open(filename, "wb") do |file|
          http.request(request) do |response|
            unless response.is_a?(Net::HTTPSuccess)
              raise DownloadError, "Download failed: #{response.code} - #{response.message}"
            end

            total_size = response["content-length"].to_i if response["content-length"]

            response.read_body do |chunk|
              file.write(chunk)
              bytes_downloaded += chunk.size

              if total_size && (bytes_downloaded % (10 * 1024 * 1024)) < chunk.size # Log every 10MB
                progress = (bytes_downloaded.to_f / total_size * 100).round(2)
                log_context(
                  :info,
                  "Download progress",
                  progress: "#{progress}%",
                  downloaded: format_bytes(bytes_downloaded),
                  total: format_bytes(total_size)
                )
              end
            end
          end
        end

        elapsed = (Time.zone.now - start_time).round(2)
        log_context(
          :info,
          "Download completed",
          filename: filename,
          size: format_bytes(bytes_downloaded),
          elapsed: "#{elapsed}s"
        )
      rescue StandardError => e
        log_context(:error, "Download failed", error: e.message, url: url)
        FileUtils.rm_f(filename) # Clean up partial download
        raise
      end

      def find_latest_archive
        archives = Dir.glob("*.tar.gz")
        log_context(
          :debug,
          "Found archives in temp directory",
          count: archives.size,
          files: archives.take(3).join(", ")
        )
        archives.max_by { |f| File.mtime(f) }
      end

      def find_dump_file
        pgsql_files = Dir.glob("*.pgsql")
        dump_files = Dir.glob("*.dump")
        sql_files = Dir.glob("*.sql")

        log_context(
          :debug,
          "Searching for dump files",
          pgsql: pgsql_files.size,
          dump:  dump_files.size,
          sql:   sql_files.size
        )

        pgsql_files.first || dump_files.first || sql_files.first
      end

      def with_retry
        attempts = 0
        begin
          attempts += 1
          yield
        rescue StandardError => e
          raise unless attempts < @max_retries && retryable_error?(e)

          log_context(:warn, "Retrying after error", attempt: attempts, max_attempts: @max_retries, error: e.message)
          sleep(@retry_delay * attempts) # Exponential backoff
          retry
        end
      end

      def retryable_error?(error)
        # Retry on network errors and timeouts
        case error
        when Net::ReadTimeout, Net::OpenTimeout, Errno::ECONNRESET, Errno::ETIMEDOUT
          true
        when StandardError
          error.message.include?("timeout") || error.message.include?("connection")
        else
          false
        end
      end

      def log_context(level, message, context={})
        formatted_context = context.map { |k, v| "#{k}=#{v}" }.join(" ")
        full_message = "[DatabaseBackupService] #{message}"
        full_message += " - #{formatted_context}" unless context.empty?

        @logger.send(level, full_message)
      end

      def format_bytes(bytes)
        return "0B" if bytes.nil? || bytes == 0

        units = %w[B KB MB GB TB]
        index = (Math.log(bytes) / Math.log(1024)).floor
        size = (bytes.to_f / (1024**index)).round(2)

        "#{size}#{units[index]}"
      end
    end
  end
end
