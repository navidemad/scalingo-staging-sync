# frozen_string_literal: true

module ScalingoStagingSync
  module Database
    # Module for validating that required columns exist before anonymization
    module ColumnValidator
      # Validates that all required columns exist for anonymization
      # @param connection [PG::Connection] Database connection
      # @param table [String] Table name to validate
      # @param required_columns [Array<String>] List of column names that must exist
      # @return [Hash] { success: Boolean, missing_columns: Array<String>, errors: Array<String> }
      def validate_columns_exist(connection, table, required_columns)
        existing_columns = fetch_table_columns(connection, table)

        if existing_columns.nil?
          return {
            success: false,
            missing_columns: [],
            errors: ["Table '#{table}' does not exist"]
          }
        end

        missing_columns = required_columns - existing_columns
        success = missing_columns.empty?

        {
          success: success,
          missing_columns: missing_columns,
          errors: success ? [] : ["Missing columns in #{table}: #{missing_columns.join(', ')}"]
        }
      end

      # Validates columns for all anonymization tables
      # @param connection [PG::Connection] Database connection
      # @return [Hash] { success: Boolean, validation_results: Hash }
      def validate_all_anonymization_columns(connection)
        validation_results = {}
        all_success = true

        ANONYMIZATION_COLUMN_REQUIREMENTS.each do |table, columns|
          result = validate_columns_exist(connection, table, columns)
          validation_results[table] = result
          all_success = false unless result[:success]
        end

        {
          success: all_success,
          validation_results: validation_results
        }
      end

      # Checks if anonymized_at column exists on a table
      # @param connection [PG::Connection] Database connection
      # @param table [String] Table name
      # @return [Boolean]
      def anonymized_at_column_exists?(connection, table)
        columns = fetch_table_columns(connection, table)
        columns&.include?("anonymized_at") || false
      end

      private

      # Required columns for each table that will be anonymized
      ANONYMIZATION_COLUMN_REQUIREMENTS = {
        "users" => %w[
          id
          email
          email_md5
          first_name
          last_name
          full_name
          credit_card_last_4
          iban_last4
          stripe_customer_id
          address_line1
          address_line2
          city
          postal_code
          birth_date
          birth_place
          billing_extra
          zendesk_user_id
        ],
        "phone_numbers" => %w[id number user_id],
        "payment_methods" => %w[id card_last4]
      }.freeze

      # Fetches all column names for a given table
      # @param connection [PG::Connection] Database connection
      # @param table [String] Table name
      # @return [Array<String>, nil] Array of column names, or nil if table doesn't exist
      def fetch_table_columns(connection, table)
        query = <<~SQL.squish
          SELECT column_name
          FROM information_schema.columns
          WHERE table_schema = 'public'
          AND table_name = $1
          ORDER BY ordinal_position
        SQL

        result = connection.exec_params(query, [table])

        return nil if result.ntuples.zero?

        result.map { |row| row["column_name"] }
      rescue PG::Error => e
        @logger&.error "[ColumnValidator] Error fetching columns for #{table}: #{e.message}"
        nil
      end
    end
  end
end
