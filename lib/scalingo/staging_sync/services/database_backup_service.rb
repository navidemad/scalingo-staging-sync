# frozen_string_literal: true

require "fileutils"
require_relative "../support/utilities"
require_relative "../integrations/scalingo_api_client"
require_relative "../support/file_downloader"
require_relative "../support/archive_handler"

module Scalingo
  module StagingSync
    class DatabaseBackupService
      include Utilities
      include ArchiveHandler

      # Import error classes from BackupService module
      BackupError = BackupService::BackupError
      AddonNotFoundError = BackupService::AddonNotFoundError
      BackupNotFoundError = BackupService::BackupNotFoundError
      DownloadError = BackupService::DownloadError

      def initialize(source_app, temp_dir, logger: Rails.logger, options: {})
        @source_app = source_app
        @temp_dir = temp_dir
        @logger = logger
        @slack_notifier = SlackNotificationService.new(logger: logger)
        @api_client = ScalingoApiClient.new(source_app, logger: logger)
        @file_downloader = FileDownloader.new(logger: logger, timeout: options[:timeout])
        FileUtils.mkdir_p(@temp_dir)
      end

      def download_and_extract!(force_download: false)
        force = should_force_download?(force_download)
        log_start_process(force)

        Dir.chdir(@temp_dir) do
          archive = get_or_download_archive(force)
          result = extract_and_prepare_backup(archive)
          finalize_process(result)
        end
      rescue StandardError => e
        handle_backup_error(e)
      end

      def should_force_download?(force_download)
        force_download || ENV["FORCE_BACKUP_DOWNLOAD"].to_s.downcase == "true"
      end

      def log_start_process(force)
        log_context(:info, "Starting download_and_extract process", app: @source_app, force_download: force)
        @slack_notifier.backup_step("📦 Téléchargement de la sauvegarde depuis #{@source_app}...")
      end

      def get_or_download_archive(force)
        archive = find_latest_archive

        if archive && !force
          use_existing_archive(archive)
        else
          handle_forced_download(archive) if archive && force
          download_new_archive
        end
      end

      def use_existing_archive(archive)
        log_context(
          :info,
          "Found existing archive, skipping download",
          archive: archive,
          size: format_bytes(File.size(archive))
        )
        @slack_notifier.backup_step("🔄 Utilisation de l'archive existante: #{File.basename(archive)}")
        archive
      end

      def handle_forced_download(archive)
        log_context(:info, "Found existing archive but forcing redownload", archive: archive)
        FileUtils.rm_f(archive)
        log_context(:info, "Removed existing archive", archive: archive)
      end

      def download_new_archive
        log_context(:info, "Initiating backup download via Scalingo API", app: @source_app)
        @slack_notifier.backup_step("📡 Récupération de la dernière sauvegarde...")

        archive = with_retry { download_backup_via_api }
        raise DownloadError, "Failed to download backup from #{@source_app}" unless archive

        log_context(:info, "Backup download completed", archive: archive, size: format_bytes(File.size(archive)))
        archive
      end

      def finalize_process(result)
        log_context(:info, "Download and extraction completed successfully", final_path: result.to_s)
        @slack_notifier.backup_step("✅ Sauvegarde prête")
        result
      end

      def handle_backup_error(error)
        log_context(
          :error,
          "Backup processing failed",
          error: error.message,
          app: @source_app,
          backtrace: error.backtrace.first(3).join(" | ")
        )
        @slack_notifier.backup_error("Échec du téléchargement")
        raise
      end

      # Archive handling methods are provided by ArchiveHandler module

      private

      def download_backup_via_api
        log_context(:info, "Starting backup download via API", app: @source_app)

        addon_id = with_retry { @api_client.postgresql_addon_id }
        db_client = with_retry { @api_client.database_client(addon_id) }
        backup_info = with_retry { @api_client.latest_backup(db_client, addon_id) }
        download_url = with_retry { @api_client.backup_download_url(db_client, addon_id, backup_info[:id]) }

        filename = "backup-#{Time.zone.now.strftime('%Y%m%d-%H%M%S')}.tar.gz"
        @file_downloader.download(download_url, filename)

        log_context(:info, "Backup download completed", filename: filename)
        filename
      end

      # File finding methods are provided by ArchiveHandler module
    end
  end
end
