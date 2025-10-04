# frozen_string_literal: true

module ScalingoStagingSync
  module Database
    # Module for detecting potential PII columns that may not be anonymized
    module PiiScanner
      # Default PII patterns to detect in column names
      DEFAULT_PII_PATTERNS = {
        identity: /\b(ssn|social_security|tax_id|passport|driver_license|national_id)\b/i,
        contact: /\b(email|phone|mobile|fax|address|street|city|postal|zip|country)\b/i,
        personal: /\b(first_name|last_name|full_name|name|birth|dob|age|gender|maiden)\b/i,
        financial: /\b(credit_card|card_number|cvv|iban|account_number|routing|salary|income)\b/i,
        auth: /\b(password|token|secret|api_key|oauth|credential)\b/i,
        medical: /\b(diagnosis|medical|prescription|health|insurance)\b/i,
        biometric: /\b(fingerprint|retina|face|dna|biometric)\b/i
      }.freeze

      # Scans all tables in the database for potential PII columns
      # @param connection [PG::Connection] Database connection
      # @param anonymized_tables [Array<String>] List of tables that are already being anonymized
      # @return [Hash] { potential_pii: Hash, warnings: Array<String> }
      def scan_for_unanonymized_pii(connection, anonymized_tables=[])
        potential_pii = {}
        warnings = []

        all_tables = fetch_all_tables(connection)
        excluded_tables = ScalingoStagingSync.configuration.exclude_tables || []
        rails_tables = %w[
          schema_migrations
          ar_internal_metadata
          action_text_rich_texts
          active_storage_attachments
          active_storage_blobs
          rmp_traces
          spatial_ref_sys
        ]
        unanonymized_tables = all_tables - anonymized_tables - excluded_tables - rails_tables

        unanonymized_tables.each do |table|
          pii_columns = scan_table_for_pii(connection, table)
          next if pii_columns.empty?

          potential_pii[table] = pii_columns
          warnings << "Table '#{table}' has potential PII columns but is not configured for anonymization: #{pii_columns.keys.join(', ')}"
        end

        {
          potential_pii: potential_pii,
          warnings: warnings
        }
      end

      # Scans a specific table for PII columns
      # @param connection [PG::Connection] Database connection
      # @param table [String] Table name
      # @return [Hash] Map of column names to detected PII types
      def scan_table_for_pii(connection, table)
        pii_columns = {}
        columns = fetch_table_columns_with_types(connection, table)

        return {} if columns.nil? || columns.empty?

        columns.each do |column_info|
          column_name = column_info["column_name"]
          data_type = column_info["data_type"]

          pii_types = detect_pii_patterns(column_name)

          # Additional heuristics based on data type
          if data_type == "character varying" && pii_types.empty? && high_cardinality?(connection, table, column_name)
            # High cardinality check for varchar columns
            pii_types << :high_cardinality
          end

          pii_columns[column_name] = pii_types unless pii_types.empty?
        end

        pii_columns
      end

      # Generates a detailed PII scan report
      # @param connection [PG::Connection] Database connection
      # @param anonymized_tables [Array<String>] List of tables being anonymized
      # @return [String] Formatted report
      def generate_pii_scan_report(connection, anonymized_tables=[])
        scan_result = scan_for_unanonymized_pii(connection, anonymized_tables)

        return "No potential unanonymized PII columns detected." if scan_result[:potential_pii].empty?

        report = ["=== PII SCAN REPORT ===", ""]
        report << "Found potential PII in #{scan_result[:potential_pii].size} unanonymized table(s):"
        report << ""

        scan_result[:potential_pii].each do |table, columns|
          report << "Table: #{table}"
          columns.each do |column, pii_types|
            report << "  - #{column}: #{pii_types.join(', ')}"
          end
          report << ""
        end

        report << "=== WARNINGS ==="
        scan_result[:warnings].each { |warning| report << warning }

        report.join("\n")
      end

      private

      # Fetches all table names from the database
      # @param connection [PG::Connection] Database connection
      # @return [Array<String>] Array of table names
      def fetch_all_tables(connection)
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
        @logger&.error "[PiiScanner] Error fetching tables: #{e.message}"
        []
      end

      # Fetches column information including data types
      # @param connection [PG::Connection] Database connection
      # @param table [String] Table name
      # @return [Array<Hash>] Array of column info hashes
      def fetch_table_columns_with_types(connection, table)
        query = <<~SQL.squish
          SELECT column_name, data_type, character_maximum_length
          FROM information_schema.columns
          WHERE table_schema = 'public'
          AND table_name = $1
          ORDER BY ordinal_position
        SQL

        result = connection.exec_params(query, [table])
        result.map { |row| row }
      rescue PG::Error => e
        @logger&.error "[PiiScanner] Error fetching columns for #{table}: #{e.message}"
        nil
      end

      # Detects PII patterns in a column name
      # @param column_name [String] Column name to check
      # @return [Array<Symbol>] Array of detected PII types
      def detect_pii_patterns(column_name)
        pii_patterns = ScalingoStagingSync.configuration.pii_detection_patterns || DEFAULT_PII_PATTERNS
        detected_types = []

        pii_patterns.each do |type, pattern|
          detected_types << type if column_name.match?(pattern)
        end

        detected_types
      end

      # Checks if a column has high cardinality (potential unique identifier)
      # @param connection [PG::Connection] Database connection
      # @param table [String] Table name
      # @param column [String] Column name
      # @return [Boolean]
      def high_cardinality?(connection, table, column)
        query = <<~SQL.squish
          SELECT
            COUNT(*) as total_rows,
            COUNT(DISTINCT #{connection.escape_identifier(column)}) as distinct_values
          FROM #{connection.escape_identifier(table)}
          WHERE #{connection.escape_identifier(column)} IS NOT NULL
          LIMIT 1
        SQL

        result = connection.exec(query)
        return false if result.ntuples.zero?

        total = result[0]["total_rows"].to_i
        distinct = result[0]["distinct_values"].to_i

        return false if total.zero?

        # High cardinality: >80% unique values
        (distinct.to_f / total) > 0.8
      rescue PG::Error => e
        @logger&.error "[PiiScanner] Error checking cardinality for #{table}.#{column}: #{e.message}"
        false
      end
    end
  end
end
