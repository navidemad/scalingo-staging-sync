# frozen_string_literal: true

module ScalingoStagingSync
  module Database
    # Module for estimating database size after excluding tables
    module SizeEstimator
      # Estimates the total database size excluding configured tables
      # @param connection [PG::Connection] Database connection
      # @return [Hash] { total_size_bytes: Integer, total_size_pretty: String, table_sizes: Array<Hash> }
      def estimate_database_size(connection)
        excluded_tables = ScalingoStagingSync.configuration.exclude_tables || []
        all_tables = fetch_all_user_tables(connection)
        included_tables = all_tables - excluded_tables

        table_sizes = fetch_table_sizes(connection, included_tables)
        total_size_bytes = table_sizes.sum { |t| t[:size_bytes] }

        {
          total_size_bytes: total_size_bytes,
          total_size_pretty: format_bytes(total_size_bytes),
          total_tables: included_tables.size,
          excluded_tables_count: excluded_tables.size,
          table_sizes: table_sizes.sort_by { |t| -t[:size_bytes] }.first(10) # Top 10 largest
        }
      rescue PG::Error => e
        @logger&.error "[SizeEstimator] Error estimating database size: #{e.message}"
        {
          total_size_bytes: 0,
          total_size_pretty: "Unknown",
          total_tables: 0,
          excluded_tables_count: excluded_tables.size,
          table_sizes: []
        }
      end

      private

      # Fetches all user tables from the database
      # @param connection [PG::Connection] Database connection
      # @return [Array<String>] Array of table names
      def fetch_all_user_tables(connection)
        query = <<~SQL.squish
          SELECT table_name
          FROM information_schema.tables
          WHERE table_schema = 'public'
          AND table_type = 'BASE TABLE'
          ORDER BY table_name
        SQL

        result = connection.exec(query)
        result.map { |row| row["table_name"] }
      rescue PG::Error => e
        @logger&.error "[SizeEstimator] Error fetching tables: #{e.message}"
        []
      end

      # Fetches sizes for specified tables
      # @param connection [PG::Connection] Database connection
      # @param tables [Array<String>] List of table names
      # @return [Array<Hash>] Array of { table: String, size_bytes: Integer, size_pretty: String }
      def fetch_table_sizes(connection, tables)
        return [] if tables.empty?

        table_list = tables.map { |t| "'#{connection.escape_string(t)}'" }.join(", ")

        query = <<~SQL.squish
          SELECT
            schemaname || '.' || tablename AS table_name,
            pg_total_relation_size(schemaname || '.' || tablename) AS size_bytes
          FROM pg_tables
          WHERE schemaname = 'public'
          AND tablename IN (#{table_list})
        SQL

        result = connection.exec(query)
        result.map do |row|
          {
            table: row["table_name"].sub("public.", ""),
            size_bytes: row["size_bytes"].to_i,
            size_pretty: format_bytes(row["size_bytes"].to_i)
          }
        end
      rescue PG::Error => e
        @logger&.error "[SizeEstimator] Error fetching table sizes: #{e.message}"
        []
      end

      # Formats bytes into human-readable format
      # @param bytes [Integer] Size in bytes
      # @return [String] Formatted size (e.g., "1.5 GB")
      def format_bytes(bytes)
        return "0 B" if bytes.zero?

        units = %w[B KB MB GB TB]
        exp = (Math.log(bytes) / Math.log(1024)).to_i
        exp = [exp, units.length - 1].min

        size = bytes.to_f / (1024**exp)
        "#{size.round(2)} #{units[exp]}"
      end
    end
  end
end
