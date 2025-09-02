# frozen_string_literal: true

module ScalingoStagingSync
  module Database
    # Module for building pg_restore and psql commands
    module RestoreCommandBuilder
      def build_pg_restore_command(backup_file, toc_file)
        cmd_parts = build_base_pg_restore_options
        cmd_parts << "-L \"#{toc_file}\"" if toc_file
        cmd_parts << "-d \"#{@pg_url}\""
        cmd_parts << "\"#{backup_file}\""

        "PG_COLOR='always' #{cmd_parts.join(' ')}"
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
        restore_cmd = "psql \"#{@pg_url}\" < \"#{backup_file}\""
        @logger.info "[DatabaseRestoreService] Executing psql restore command..."

        return if system(restore_cmd)

        @logger.error "[DatabaseRestoreService] psql restore failed"
        @slack_notifier.restore_error("Échec restauration psql")
        raise "Database restore failed with psql"
      end
    end
  end
end
