# frozen_string_literal: true

require_relative "environment_validator"
require_relative "coordinator_helpers"

module Scalingo
  module StagingSync
    class StagingSyncCoordinator
      include EnvironmentValidator
      include CoordinatorHelpers

      def initialize(logger: nil)
        @config = Scalingo::StagingSync.configuration

        @logger = logger || @config.logger
        @temp_dir = @config.temp_dir
        @start_time = Time.current
        @slack_notifier = Scalingo::StagingSync::SlackNotificationService.new(logger: @logger)

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
          log_sync_start
          notify_start

          perform_sync_steps
          finalize_sync
        end
      rescue StandardError => e
        handle_error(e)
      end

      def log_sync_start
        @logger.info "[StagingSyncCoordinator] Starting staging sync process"
        @logger.info "[StagingSyncCoordinator] Source: #{@source_app}"
        @logger.info "[StagingSyncCoordinator] Target: #{@target_app}"
        seeds_status = @config.seeds_file_path ? "#{@config.seeds_file_path} will run" : "none configured"
        @logger.info "[StagingSyncCoordinator] Seeds: #{seeds_status}"
      end

      def perform_sync_steps
        backup_file = execute_step(1, "Downloading backup") { download_backup }
        execute_step(2, "Restoring database") { restore_database(backup_file) }
        execute_step(3, "Anonymizing data") { anonymize_data }
        execute_step(4, "Running staging seeds") { run_staging_seeds }
      end

      def execute_step(step_number, description)
        @logger.info "[StagingSyncCoordinator] Step #{step_number}: #{description}"
        yield
      end

      def finalize_sync
        notify_success
        cleanup_temp_files
        duration = ((Time.current - @start_time) / 60).round(2)
        @logger.info "[StagingSyncCoordinator] ✅ Staging sync completed successfully in #{duration} minutes"
      end

      private

      def download_backup
        notify_step("📥 *Étape 1/4*: Téléchargement sauvegarde")
        @logger.info "[StagingSyncCoordinator] Initializing DatabaseBackupService"

        service = Scalingo::StagingSync::DatabaseBackupService.new(@source_app, @temp_dir, logger: @logger)

        @logger.info "[StagingSyncCoordinator] Calling download_and_extract!"
        result = service.download_and_extract!

        @logger.info "[StagingSyncCoordinator] Backup downloaded successfully: #{result}"
        result
      end

      def restore_database(backup_file)
        notify_step("💾 *Étape 2/4*: Restauration base de données")
        @logger.info "[StagingSyncCoordinator] Initializing DatabaseRestoreService"

        service = Scalingo::StagingSync::DatabaseRestoreService.new(@database_url, logger: @logger)

        exclude_tables = @config.exclude_tables || []
        @logger.info "[StagingSyncCoordinator] Excluded tables: #{exclude_tables.join(', ')}" if exclude_tables.any?

        @logger.info "[StagingSyncCoordinator] Calling restore! with backup file: #{backup_file}"
        service.restore!(backup_file, exclude_tables: exclude_tables)

        @logger.info "[StagingSyncCoordinator] Database restoration completed"
      end

      def anonymize_data
        notify_step("🔐 *Étape 3/4*: Anonymisation des données")
        @logger.info "[StagingSyncCoordinator] Initializing DatabaseAnonymizerService"

        service = Scalingo::StagingSync::DatabaseAnonymizerService.new(@database_url, logger: @logger)

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

      # Notification and cleanup methods are provided by CoordinatorHelpers module
    end
  end
end
