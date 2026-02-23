# frozen_string_literal: true

require "open3"
require_relative "../database/database_operations"
require_relative "../database/toc_filter"
require_relative "../database/restore_command_builder"

module ScalingoStagingSync
  module Services
    class DatabaseRestoreService
      include Database::DatabaseOperations
      include Database::TocFilter
      include Database::RestoreCommandBuilder

      def initialize(database_url, logger: Rails.logger)
        @database_url = database_url
        @pg_url = database_url
        @logger = logger
        @slack_notifier = Services::SlackNotificationService.new(logger: logger)
      end

      def restore!(backup_file, toc_file: nil, exclude_tables: [])
        log_restore_start(backup_file, exclude_tables)
        toc_file = prepare_toc_if_needed(backup_file, toc_file, exclude_tables)
        perform_restore(backup_file, toc_file)
        finalize_restore
      rescue StandardError => e
        handle_restore_error(e)
      end

      private

      def log_restore_start(backup_file, exclude_tables)
        @logger.info "[DatabaseRestoreService] Starting database restore process..."
        @slack_notifier.restore_step("💾 Restauration de la base de données...")
        @logger.info "[DatabaseRestoreService] Backup file: #{backup_file}"
        @logger.info "[DatabaseRestoreService] Excluded tables: #{exclude_tables.join(', ')}" if exclude_tables.any?
      end

      def prepare_toc_if_needed(backup_file, toc_file, exclude_tables)
        return toc_file unless exclude_tables.any? && toc_file.nil?

        generate_filtered_toc(backup_file, exclude_tables)
      end

      def perform_restore(backup_file, toc_file)
        @logger.info "[DatabaseRestoreService] Checking available restore methods..."
        if pg_restore_available?
          @logger.info "[DatabaseRestoreService] Using pg_restore for database restoration"
          restore_with_pg_restore(backup_file, toc_file)
        else
          @logger.warn "[DatabaseRestoreService] pg_restore not available, falling back to psql"
          restore_with_psql(backup_file)
        end
      end

      def finalize_restore
        @logger.info "[DatabaseRestoreService] Running database migrations..."
        run_migrations

        @logger.info "[DatabaseRestoreService] Checking installed PostgreSQL extensions..."
        display_installed_extensions

        @logger.info "[DatabaseRestoreService] ✅ Database restore completed successfully"
        @slack_notifier.restore_step("✅ Base de données restaurée avec succès")
      end

      def handle_restore_error(error)
        @logger.error "[DatabaseRestoreService] Restore failed: #{error.message}"
        @logger.error "[DatabaseRestoreService] Backtrace: #{error.backtrace.first(5).join('\n')}"
        @slack_notifier.restore_error("Échec de la restauration")
        raise
      end

      def pg_restore_available?
        _stdout, _stderr, status = Open3.capture3("which", "pg_restore")
        available = status.success?
        @logger.debug "[DatabaseRestoreService] pg_restore availability: #{available}"
        available
      end

      def restore_with_pg_restore(backup_file, toc_file)
        @logger.info "[DatabaseRestoreService] Starting pg_restore " \
                     "(parallel mode, excluding pghero/heroku_ext schemas)..."
        @slack_notifier.restore_step("🔄 Restauration avec pg_restore")

        recreate_database
        execute_pg_restore(backup_file, toc_file)

        @logger.info "[DatabaseRestoreService] ✓ pg_restore completed successfully"
        @slack_notifier.restore_step("✓ Données restaurées")
      end

      def execute_pg_restore(backup_file, toc_file)
        restore_cmd = build_pg_restore_command(backup_file, toc_file)
        env = pg_restore_env
        @logger.info "[DatabaseRestoreService] Executing pg_restore command..."
        @logger.debug "[DatabaseRestoreService] Command: #{restore_cmd.join(' ')}"

        output, error, status = Open3.capture3(env, *restore_cmd)
        @logger.debug "[DatabaseRestoreService] pg_restore output lines: #{output.lines.size}"

        return if status.success?

        @logger.error "[DatabaseRestoreService] pg_restore failed with exit code: #{status.exitstatus}"
        @logger.error "[DatabaseRestoreService] Error output: #{error}"
        @slack_notifier.restore_error("Échec pg_restore (code: #{status.exitstatus})")
        raise "Database restore failed with pg_restore"
      end

      def restore_with_psql(backup_file)
        @logger.warn "[DatabaseRestoreService] pg_restore not found, using psql fallback..."
        @slack_notifier.restore_step("⚠️ Utilisation de psql (fallback)")
        execute_psql_restore(backup_file)
        @logger.info "[DatabaseRestoreService] ✓ psql restore completed"
      end

      # Restore command building methods are provided by RestoreCommandBuilder module
    end
  end
end
