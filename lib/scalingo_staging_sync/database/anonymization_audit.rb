# frozen_string_literal: true

require "digest"
require "json"

module ScalingoStagingSync
  module Database
    # Module for creating audit trails of anonymization operations
    module AnonymizationAudit
      # Captures pre-anonymization state of a table
      # @param connection [PG::Connection] Database connection
      # @param table [String] Table name
      # @return [Hash] Pre-anonymization audit data
      def capture_pre_anonymization_state(connection, table)
        {
          table: table,
          timestamp: Time.current.iso8601,
          row_count: get_row_count(connection, table),
          sample_hash: generate_sample_hash(connection, table),
          column_stats: capture_column_statistics(connection, table)
        }
      end

      # Captures post-anonymization state of a table
      # @param connection [PG::Connection] Database connection
      # @param table [String] Table name
      # @param rows_affected [Integer] Number of rows anonymized
      # @return [Hash] Post-anonymization audit data
      def capture_post_anonymization_state(connection, table, rows_affected)
        {
          table: table,
          timestamp: Time.current.iso8601,
          rows_affected: rows_affected,
          row_count: get_row_count(connection, table),
          sample_hash: generate_sample_hash(connection, table),
          column_stats: capture_column_statistics(connection, table)
        }
      end

      # Generates a complete anonymization audit report
      # @param audit_records [Array<Hash>] Array of audit record pairs (before/after)
      # @param verification_results [Hash] Verification results for all tables
      # @param pii_scan_results [Hash] PII scan results
      # @return [Hash] Complete audit report
      def generate_audit_report(audit_records, verification_results, pii_scan_results)
        {
          generated_at: Time.current.iso8601,
          summary: generate_summary(audit_records, verification_results),
          tables: audit_records,
          verification: verification_results,
          pii_scan: pii_scan_results,
          metadata: {
            gem_version: ScalingoStagingSync::VERSION,
            database_url_host: ENV["DATABASE_URL"]&.match(%r{//([^:@]+)}i)&.captures&.first,
            environment: ENV.fetch("APP", nil)
          }
        }
      end

      # Formats audit report as human-readable text
      # @param report [Hash] Audit report
      # @return [String] Formatted report
      def format_audit_report(report)
        lines = []
        lines << ("=" * 80)
        lines << "ANONYMIZATION AUDIT REPORT"
        lines << ("=" * 80)
        lines << ""
        lines << "Generated: #{report[:generated_at]}"
        lines << "Environment: #{report[:metadata][:environment]}"
        lines << "Gem Version: #{report[:metadata][:gem_version]}"
        lines << ""

        # Summary section
        lines << "SUMMARY"
        lines << ("-" * 80)
        lines << "Total Tables Anonymized: #{report[:summary][:total_tables]}"
        lines << "Total Rows Affected: #{report[:summary][:total_rows_affected]}"
        lines << "Verification Passed: #{report[:summary][:verification_passed] ? 'YES' : 'NO'}"
        lines << "PII Scan Warnings: #{report[:summary][:pii_warnings_count]}"
        lines << ""

        # Table details
        lines << "TABLE DETAILS"
        lines << ("-" * 80)
        report[:tables].each do |table_audit|
          lines << format_table_audit(table_audit)
          lines << ""
        end

        # Verification results
        if report[:verification].any?
          lines << "VERIFICATION RESULTS"
          lines << ("-" * 80)
          report[:verification].each do |table, result|
            lines << format_verification_result(table, result)
          end
          lines << ""
        end

        # PII scan results
        if report[:pii_scan][:warnings]&.any?
          lines << "PII SCAN WARNINGS"
          lines << ("-" * 80)
          report[:pii_scan][:warnings].each { |warning| lines << "  - #{warning}" }
          lines << ""
        end

        lines << ("=" * 80)
        lines.join("\n")
      end

      # Saves audit report to file
      # @param report [Hash] Audit report
      # @param file_path [String] Path to save the report
      def save_audit_report(report, file_path)
        # Save JSON version
        json_path = file_path.sub(/\.(txt|log)$/i, ".json")
        File.write(json_path, JSON.pretty_generate(report))

        # Save human-readable version
        txt_path = file_path.sub(/\.json$/i, ".txt")
        File.write(txt_path, format_audit_report(report))

        @logger&.info "[AnonymizationAudit] Audit report saved to: #{json_path} and #{txt_path}"

        { json: json_path, text: txt_path }
      end

      private

      # Gets row count for a table
      # @param connection [PG::Connection] Database connection
      # @param table [String] Table name
      # @return [Integer] Row count
      def get_row_count(connection, table)
        query = "SELECT COUNT(*) FROM #{connection.escape_identifier(table)}"
        result = connection.exec(query)
        result[0]["count"].to_i
      rescue PG::Error => e
        @logger&.error "[AnonymizationAudit] Error getting row count for #{table}: #{e.message}"
        0
      end

      # Generates a hash of sample data (for verification that data changed)
      # @param connection [PG::Connection] Database connection
      # @param table [String] Table name
      # @return [String] SHA256 hash of sample data
      def generate_sample_hash(connection, table)
        query = <<~SQL.squish
          SELECT *
          FROM #{connection.escape_identifier(table)}
          ORDER BY id
          LIMIT 100
        SQL

        result = connection.exec(query)
        sample_data = result.map { |row| row.values.join("|") }.join("\n")
        Digest::SHA256.hexdigest(sample_data)
      rescue PG::Error => e
        @logger&.error "[AnonymizationAudit] Error generating sample hash for #{table}: #{e.message}"
        "error"
      end

      # Captures column statistics (null counts, distinct values, etc.)
      # @param connection [PG::Connection] Database connection
      # @param table [String] Table name
      # @return [Hash] Column statistics
      def capture_column_statistics(connection, table)
        columns = fetch_table_columns(connection, table)
        return {} if columns.nil? || columns.empty?

        stats = {}

        # Limit to first 10 columns to avoid performance issues
        columns.take(10).each do |column|
          stats[column] = {
            null_count: get_null_count(connection, table, column),
            distinct_count: get_distinct_count(connection, table, column)
          }
        end

        stats
      rescue PG::Error => e
        @logger&.error "[AnonymizationAudit] Error capturing column stats for #{table}: #{e.message}"
        {}
      end

      # Gets null count for a column
      # @param connection [PG::Connection] Database connection
      # @param table [String] Table name
      # @param column [String] Column name
      # @return [Integer] Null count
      def get_null_count(connection, table, column)
        query = <<~SQL.squish
          SELECT COUNT(*)
          FROM #{connection.escape_identifier(table)}
          WHERE #{connection.escape_identifier(column)} IS NULL
        SQL

        result = connection.exec(query)
        result[0]["count"].to_i
      rescue PG::Error
        0
      end

      # Gets distinct count for a column
      # @param connection [PG::Connection] Database connection
      # @param table [String] Table name
      # @param column [String] Column name
      # @return [Integer] Distinct count
      def get_distinct_count(connection, table, column)
        query = <<~SQL.squish
          SELECT COUNT(DISTINCT #{connection.escape_identifier(column)})
          FROM #{connection.escape_identifier(table)}
        SQL

        result = connection.exec(query)
        result[0]["count"].to_i
      rescue PG::Error
        0
      end

      # Fetches column names for a table
      # @param connection [PG::Connection] Database connection
      # @param table [String] Table name
      # @return [Array<String>] Column names
      def fetch_table_columns(connection, table)
        query = <<~SQL.squish
          SELECT column_name
          FROM information_schema.columns
          WHERE table_schema = 'public'
          AND table_name = $1
          ORDER BY ordinal_position
        SQL

        result = connection.exec_params(query, [table])
        result.map { |row| row["column_name"] }
      rescue PG::Error
        []
      end

      # Generates summary statistics
      # @param audit_records [Array<Hash>] Audit records
      # @param verification_results [Hash] Verification results
      # @return [Hash] Summary statistics
      def generate_summary(audit_records, verification_results)
        total_rows = audit_records.sum { |record| record[:after][:rows_affected] || 0 }
        verification_passed = verification_results.values.all? { |result| result[:success] }
        pii_warnings = verification_results.values.sum { |result| result[:warnings]&.size || 0 }

        {
          total_tables: audit_records.size,
          total_rows_affected: total_rows,
          verification_passed: verification_passed,
          pii_warnings_count: pii_warnings
        }
      end

      # Formats a single table audit
      # @param table_audit [Hash] Table audit data
      # @return [String] Formatted table audit
      def format_table_audit(table_audit)
        before = table_audit[:before]
        after = table_audit[:after]

        lines = []
        lines << "Table: #{before[:table]}"
        lines << "  Before: #{before[:row_count]} rows (hash: #{before[:sample_hash][0..12]}...)"
        lines << "  After:  #{after[:row_count]} rows (hash: #{after[:sample_hash][0..12]}...)"
        lines << "  Rows Affected: #{after[:rows_affected]}"
        lines << "  Data Changed: #{before[:sample_hash] == after[:sample_hash] ? 'NO' : 'YES'}"

        lines.join("\n")
      end

      # Formats verification result for a table
      # @param table [String] Table name
      # @param result [Hash] Verification result
      # @return [String] Formatted verification result
      def format_verification_result(table, result)
        lines = []
        lines << "#{table}:"
        lines << "  Status: #{result[:success] ? 'PASSED' : 'FAILED'}"

        if result[:issues]&.any?
          lines << "  Issues:"
          result[:issues].each { |issue| lines << "    - #{issue}" }
        end

        if result[:warnings]&.any?
          lines << "  Warnings:"
          result[:warnings].each { |warning| lines << "    - #{warning}" }
        end

        lines.join("\n")
      end
    end
  end
end
