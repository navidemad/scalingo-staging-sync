# frozen_string_literal: true

require "open3"

module ScalingoStagingSync
  module Database
    # Module for building pg_restore and psql commands
    module RestoreCommandBuilder
      def build_pg_restore_command(backup_file, toc_file)
        cmd_parts = build_base_pg_restore_options
        cmd_parts << "-L" << toc_file if toc_file
        cmd_parts << "-d" << @pg_url
        cmd_parts << backup_file

        cmd_parts
      end

      def pg_restore_env
        { "PG_COLOR" => "always" }
      end

      def build_base_pg_restore_options
        [
          "pg_restore",
          "--verbose",
          "--no-owner",
          "--no-acl",
          "--no-privileges",
          "--no-subscriptions",
          "--no-security-labels",
          "--no-publications",
          "--no-comments",
          "--no-tablespaces",
          "--exclude-schema=pghero",
          "--exclude-schema=heroku_ext",
          "--jobs=4"
        ]
      end

      def execute_psql_restore(backup_file)
        @logger.info "[DatabaseRestoreService] Executing psql restore command..."

        # Read the backup file and pipe it to psql using Open3
        output, error, status = Open3.capture3("psql", @pg_url, stdin_data: File.read(backup_file))

        if status.success?
          @logger.debug "[DatabaseRestoreService] psql output: #{output}" if output && !output.empty?
          return
        end

        @logger.error "[DatabaseRestoreService] psql restore failed with exit code: #{status.exitstatus}"
        @logger.error "[DatabaseRestoreService] Error output: #{error}" if error && !error.empty?
        @slack_notifier.restore_error("Échec restauration psql")
        raise "Database restore failed with psql"
      end
    end
  end
end
