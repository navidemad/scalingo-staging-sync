# frozen_string_literal: true

module ScalingoStagingSync
  module Testing
    # Module for logging database connection information
    module DatabaseInfoLogger
      def log_database_info(connection)
        log_postgresql_version(connection)
        log_database_size(connection)
        log_table_count(connection)
      end

      private

      def log_postgresql_version(connection)
        result = connection.exec("SELECT version()")
        pg_version = result.first["version"].split[1]
        pass "PostgreSQL connection successful (v#{pg_version})"
        @logger.info "[Tester] PostgreSQL connection successful - version #{pg_version}"
      end

      def log_database_size(connection)
        size_result = connection.exec("SELECT pg_database_size(current_database())")
        db_size_mb = (size_result.first["pg_database_size"].to_i / 1024.0 / 1024.0).round(2)
        info "  Database size: #{db_size_mb} MB"
      end

      def log_table_count(connection)
        tables_result = connection.exec(
          "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public'"
        )
        table_count = tables_result.first["count"]
        info "  Public tables: #{table_count}"
      end
    end
  end
end
