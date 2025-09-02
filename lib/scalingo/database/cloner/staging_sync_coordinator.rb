# frozen_string_literal: true

module Scalingo
  module Database
    module Cloner
      class StagingSyncCoordinator
        def initialize(logger: nil)
          @config = Scalingo::Database::Cloner.configuration

          @logger = logger || @config.logger
          @temp_dir = @config.temp_dir
          @start_time = Time.current
          @slack_notifier = Scalingo::Database::Cloner::SlackNotificationService.new(logger: @logger)

          # Get app names from configuration
          @target_app = @config.target_app
          @source_app = @config.clone_source_scalingo_app_name

          # Log which source is being used for target_app
          if ENV["APP"]
            @logger.info "[StagingSyncCoordinator] Using ENV['APP'] for target: #{@target_app}"
          else
            @logger.info "[StagingSyncCoordinator] Using configuration for target: #{@target_app}"
          end
        end

        def execute!
          validate_environment!

          @logger.tagged("DEMO_SYNC") do
            @logger.info "[StagingSyncCoordinator] Starting staging sync process"
            @logger.info "[StagingSyncCoordinator] Source: #{@source_app}"
            @logger.info "[StagingSyncCoordinator] Target: #{@target_app}"
            seeds_status = @config.seeds_file_path ? "#{@config.seeds_file_path} will run" : "none configured"
            @logger.info "[StagingSyncCoordinator] Seeds: #{seeds_status}"

            notify_start

            # Step 1: Download backup
            @logger.info "[StagingSyncCoordinator] Step 1: Downloading backup"
            backup_file = download_backup

            # Step 2: Restore database
            @logger.info "[StagingSyncCoordinator] Step 2: Restoring database"
            restore_database(backup_file)

            # Step 3: Anonymize data
            @logger.info "[StagingSyncCoordinator] Step 3: Anonymizing data"
            anonymize_data

            # Step 4: Run seeds
            @logger.info "[StagingSyncCoordinator] Step 4: Running staging seeds"
            run_staging_seeds

            # Success!
            notify_success
            cleanup_temp_files

            duration = ((Time.current - @start_time) / 60).round(2)
            @logger.info "[StagingSyncCoordinator] ✅ Staging sync completed successfully in #{duration} minutes"
          end
        rescue StandardError => e
          handle_error(e)
        end

        private

        def validate_environment!
          @logger.info "[StagingSyncCoordinator] Validating environment and safety checks..."

          if Rails.env.production?
            @logger.error "[StagingSyncCoordinator] CRITICAL: Attempted to run in production environment!"
            raise "CRITICAL: Cannot run in production!"
          end
          @logger.info "[StagingSyncCoordinator] ✓ Rails environment check passed: #{Rails.env}"

          if ENV["APP"]&.include?("prod")
            @logger.error "[StagingSyncCoordinator] App name contains 'prod': #{ENV.fetch('APP', nil)}"
            raise "App name contains 'prod' - stopping for safety"
          end
          @logger.info "[StagingSyncCoordinator] ✓ App name check passed: #{ENV['APP'] || 'not set'}"

          database_url = ENV["DATABASE_URL"] || ENV.fetch("SCALINGO_POSTGRESQL_URL", nil)
          unless database_url
            @logger.error "[StagingSyncCoordinator] No database URL found in environment"
            raise "No DATABASE_URL found"
          end

          @database_url = database_url
          @logger.info "[StagingSyncCoordinator] ✓ Database URL configured"
          @logger.info "[StagingSyncCoordinator] All safety checks passed - proceeding with sync"
        end

        def download_backup
          notify_step("📥 *Étape 1/4*: Téléchargement sauvegarde")
          @logger.info "[StagingSyncCoordinator] Initializing DatabaseBackupService"

          service = Scalingo::Database::Cloner::DatabaseBackupService.new(@source_app, @temp_dir, logger: @logger)

          @logger.info "[StagingSyncCoordinator] Calling download_and_extract!"
          result = service.download_and_extract!

          @logger.info "[StagingSyncCoordinator] Backup downloaded successfully: #{result}"
          result
        end

        def restore_database(backup_file)
          notify_step("💾 *Étape 2/4*: Restauration base de données")
          @logger.info "[StagingSyncCoordinator] Initializing DatabaseRestoreService"

          service = Scalingo::Database::Cloner::DatabaseRestoreService.new(@database_url, logger: @logger)

          exclude_tables = @config.exclude_tables || []
          @logger.info "[StagingSyncCoordinator] Excluded tables: #{exclude_tables.join(', ')}" if exclude_tables.any?

          @logger.info "[StagingSyncCoordinator] Calling restore! with backup file: #{backup_file}"
          service.restore!(backup_file, exclude_tables: exclude_tables)

          @logger.info "[StagingSyncCoordinator] Database restoration completed"
        end

        def anonymize_data
          notify_step("🔐 *Étape 3/4*: Anonymisation des données")
          @logger.info "[StagingSyncCoordinator] Initializing DatabaseAnonymizerService"

          service = Scalingo::Database::Cloner::DatabaseAnonymizerService.new(@database_url, logger: @logger)

          @logger.info "[StagingSyncCoordinator] Starting data anonymization"
          service.anonymize!

          @logger.info "[StagingSyncCoordinator] Data anonymization completed"
        end

        def run_staging_seeds
          notify_step("🌱 *Étape 4/4*: Création comptes de test")
          @logger.info "[StagingSyncCoordinator] Running staging seeds"

          if @config.seeds_file_path.nil?
            @logger.info "[StagingSyncCoordinator] No seeds file configured - skipping seeding step"
            @slack_notifier.coordinator_step("⚠️ Aucun fichier de seeds configuré")
            return
          end

          if File.exist?(@config.seeds_file_path)
            @logger.info "[StagingSyncCoordinator] Loading seeds from: #{@config.seeds_file_path}"
            load @config.seeds_file_path
            @logger.info "[StagingSyncCoordinator] ✓ Staging seeds executed successfully"
            @slack_notifier.coordinator_step("✓ Comptes de test créés")
          else
            @logger.warn "[StagingSyncCoordinator] Configured seeds file not found: #{@config.seeds_file_path}"
            @slack_notifier.coordinator_step("⚠️ Fichier seeds configuré introuvable")
          end
        end

        def cleanup_temp_files
          @logger.info "[StagingSyncCoordinator] Cleaning up temporary files..."

          temp_files =
            %w[production.tar.gz production.dump production.pgsql latest.pgsql filtered.toc].map do |f|
              @temp_dir.join(f)
            end

          cleaned_count = 0
          temp_files.each do |file|
            next unless File.exist?(file)

            FileUtils.rm_f(file)
            cleaned_count += 1
            @logger.debug "[StagingSyncCoordinator] Removed: #{file}"
          end

          @logger.info "[StagingSyncCoordinator] Cleaned up #{cleaned_count} temporary files"
        end

        def notify_start
          message = "🚀 Démarrage (Application cible: #{@target_app})"
          @logger.info "[StagingSyncCoordinator] Sending start notification: #{message}"
          @slack_notifier.coordinator_step(message)
        end

        def notify_step(message)
          @logger.info "[StagingSyncCoordinator] #{message}"
          @slack_notifier.coordinator_step(message)
        end

        def notify_success
          duration_minutes = ((Time.current - @start_time) / 60).round

          @logger.info "[StagingSyncCoordinator] Sync completed in #{duration_minutes} minutes"

          @slack_notifier.notify_success(duration_minutes, @source_app, @target_app)
        end

        def handle_error(error)
          @logger.error "[StagingSyncCoordinator] Staging sync failed: #{error.message}"
          @logger.error "[StagingSyncCoordinator] Backtrace:\n#{error.backtrace.first(10).join("\n")}"

          @slack_notifier.notify_failure(error.message, @target_app)

          @logger.info "[StagingSyncCoordinator] Performing emergency cleanup..."
          cleanup_temp_files
          raise error
        end
      end
    end
  end
end
