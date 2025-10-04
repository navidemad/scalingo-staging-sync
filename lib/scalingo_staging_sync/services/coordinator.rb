# frozen_string_literal: true

require_relative "../support/environment_validator"
require_relative "../support/coordinator_helpers"

module ScalingoStagingSync
  module Services
    class Coordinator
      include Support::EnvironmentValidator
      include Support::CoordinatorHelpers

      def initialize(logger: nil)
        @config = ScalingoStagingSync.configuration

        @logger = logger || @config.logger
        @temp_dir = @config.temp_dir
        @start_time = Time.current
        @slack_notifier = Services::SlackNotificationService.new(logger: @logger)

        # Get app names from configuration
        @target_app = @config.target_app
        @source_app = @config.clone_source_scalingo_app_name

        # Log which source is being used for target_app
        if ENV["APP"]
          @logger.info "[Coordinator] Using ENV['APP'] for target: #{@target_app}"
        else
          @logger.info "[Coordinator] Using configuration for target: #{@target_app}"
        end
      end

      def execute!
        validate_environment!

        @logger.tagged("SCALINGO_STAGING_SYNC") do
          log_sync_start
          notify_start

          perform_sync_steps
          finalize_sync
        end
      rescue StandardError => e
        handle_error(e)
      end

      def log_sync_start
        @logger.info "[Coordinator] Starting staging sync process"
        @logger.info "[Coordinator] Source: #{@source_app}"
        @logger.info "[Coordinator] Target: #{@target_app}"
        seeds_status = @config.seeds_file_path ? "#{@config.seeds_file_path} will run" : "none configured"
        @logger.info "[Coordinator] Seeds: #{seeds_status}"
      end

      def perform_sync_steps
        if @config.dry_run
          perform_dry_run_steps
        else
          backup_file = execute_step(1, "Downloading backup") { download_backup }
          execute_step(2, "Restoring database") { restore_database(backup_file) }
          execute_step(3, "Anonymizing data") { anonymize_data }
          execute_step(4, "Running staging seeds") { run_staging_seeds }
        end
      end

      def perform_dry_run_steps
        @logger.info "[Coordinator] [DRY RUN] Step 1: Would download backup from '#{@source_app}'"
        @logger.info "[Coordinator] [DRY RUN] Step 2: Would restore database to '#{@target_app}'"
        @logger.info "[Coordinator] [DRY RUN] Step 3: Would anonymize data using configured strategies"
        @logger.info "[Coordinator] [DRY RUN] Step 4: Would run staging seeds from: #{@config.seeds_file_path || 'none configured'}"
        @logger.info "[Coordinator] [DRY RUN] Configuration validated successfully. All steps would execute correctly."
      end

      def execute_step(step_number, description)
        @logger.info "[Coordinator] Step #{step_number}: #{description}"
        yield
      end

      def finalize_sync
        notify_success
        cleanup_temp_files
        duration = ((Time.current - @start_time) / 60).round(2)
        @logger.info "[Coordinator] ✅ Staging sync completed successfully in #{duration} minutes"
      end

      private

      def download_backup
        notify_step("📥 *Étape 1/4*: Téléchargement sauvegarde")
        @logger.info "[Coordinator] Initializing DatabaseBackupService"

        service = ScalingoStagingSync::Services::DatabaseBackupService.new(@source_app, @temp_dir, logger: @logger)

        @logger.info "[Coordinator] Calling download_and_extract!"
        result = service.download_and_extract!

        @logger.info "[Coordinator] Backup downloaded successfully: #{result}"
        result
      end

      def restore_database(backup_file)
        notify_step("💾 *Étape 2/4*: Restauration base de données")
        @logger.info "[Coordinator] Initializing DatabaseRestoreService"

        service = ScalingoStagingSync::Services::DatabaseRestoreService.new(@database_url, logger: @logger)

        exclude_tables = @config.exclude_tables || []
        @logger.info "[Coordinator] Excluded tables: #{exclude_tables.join(', ')}" if exclude_tables.any?

        @logger.info "[Coordinator] Calling restore! with backup file: #{backup_file}"
        service.restore!(backup_file, exclude_tables: exclude_tables)

        @logger.info "[Coordinator] Database restoration completed"
      end

      def anonymize_data
        notify_step("🔐 *Étape 3/4*: Anonymisation des données")
        @logger.info "[Coordinator] Initializing DatabaseAnonymizerService"

        service = ScalingoStagingSync::Services::DatabaseAnonymizerService.new(@database_url, logger: @logger)

        @logger.info "[Coordinator] Starting data anonymization"
        service.anonymize!

        @logger.info "[Coordinator] Data anonymization completed"
      end

      def run_staging_seeds
        notify_step("🌱 *Étape 4/4*: Création comptes de test")
        @logger.info "[Coordinator] Running staging seeds"

        if @config.seeds_file_path.nil?
          @logger.info "[Coordinator] No seeds file configured - skipping seeding step"
          @slack_notifier.coordinator_step("⚠️ Aucun fichier de seeds configuré")
          return
        end

        if File.exist?(@config.seeds_file_path)
          @logger.info "[Coordinator] Loading seeds from: #{@config.seeds_file_path}"
          load @config.seeds_file_path
          @logger.info "[Coordinator] ✓ Staging seeds executed successfully"
          @slack_notifier.coordinator_step("✓ Comptes de test créés")
        else
          @logger.warn "[Coordinator] Configured seeds file not found: #{@config.seeds_file_path}"
          @slack_notifier.coordinator_step("⚠️ Fichier seeds configuré introuvable")
        end
      end

      # Notification and cleanup methods are provided by CoordinatorHelpers module
    end
  end
end
