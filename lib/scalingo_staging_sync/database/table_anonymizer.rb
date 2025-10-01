# frozen_string_literal: true

module ScalingoStagingSync
  module Database
    # Module for individual table anonymization operations with transaction support
    module TableAnonymizer
      def anonymize_users_table(connection)
        anonymize_table_with_transaction(
          connection: connection,
          table_name: "users",
          query: users_anonymization_query,
          where_clause: "anonymized_at IS NULL",
          description: "email, names, personal data"
        )
      end

      def anonymize_phone_numbers_table(connection)
        anonymize_table_with_transaction(
          connection: connection,
          table_name: "phone_numbers",
          query: phone_numbers_anonymization_query,
          description: "phone numbers"
        )
      end

      def anonymize_payment_methods_table(connection)
        anonymize_table_with_transaction(
          connection: connection,
          table_name: "payment_methods",
          query: payment_methods_anonymization_query,
          description: "card details"
        )
      end

      def handle_unknown_table(table)
        @logger.warn "[DatabaseAnonymizerService] Unknown table: #{table} - skipping"
      end

      private

      # Executes anonymization query within a savepoint transaction with retry logic
      #
      # @param connection [PG::Connection] Database connection
      # @param table_name [String] Name of the table being anonymized
      # @param query [String] SQL anonymization query
      # @param where_clause [String, nil] Optional WHERE clause for verification
      # @param description [String] Human-readable description for logging
      # @return [Integer] Number of rows affected
      def anonymize_table_with_transaction(connection:, table_name:, query:, where_clause: nil, description: "")
        description_text = description.empty? ? "" : " (#{description})"
        @logger.info "[DatabaseAnonymizerService] Anonymizing #{table_name} table#{description_text}..."

        rows_affected = with_retry(
          max_attempts: ScalingoStagingSync.configuration.anonymization_retry_attempts,
          base_delay: ScalingoStagingSync.configuration.anonymization_retry_delay,
          table_name: table_name
        ) do
          with_transaction(connection, savepoint_name: "anon_#{table_name}") do
            result = connection.exec(query)
            rows = result.cmd_tuples

            # Verify the anonymization if verification is enabled
            if ScalingoStagingSync.configuration.verify_anonymization && !verify_anonymization(
              connection,
              table_name,
              rows,
              where_clause: where_clause
            )
              raise PG::Error, "Verification failed for #{table_name}"
            end

            rows
          end
        end

        @logger.info "[DatabaseAnonymizerService] #{table_name.capitalize} table: #{rows_affected} rows anonymized"
        rows_affected
      end
    end
  end
end
