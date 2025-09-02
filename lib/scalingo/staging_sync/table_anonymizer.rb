# frozen_string_literal: true

module Scalingo
  module StagingSync
    # Module for individual table anonymization operations
    module TableAnonymizer
      def anonymize_users_table(connection)
        @logger.info "[DatabaseAnonymizerService] Anonymizing users table (email, names, personal data)..."
        result = connection.exec(users_anonymization_query)
        rows = result.cmd_tuples
        @logger.info "[DatabaseAnonymizerService] Users table: #{rows} rows anonymized"
        rows
      end

      def anonymize_phone_numbers_table(connection)
        @logger.info "[DatabaseAnonymizerService] Anonymizing phone_numbers table..."
        result = connection.exec(phone_numbers_anonymization_query)
        rows = result.cmd_tuples
        @logger.info "[DatabaseAnonymizerService] Phone numbers table: #{rows} rows anonymized"
        rows
      end

      def anonymize_payment_methods_table(connection)
        @logger.info "[DatabaseAnonymizerService] Anonymizing payment_methods table..."
        result = connection.exec(payment_methods_anonymization_query)
        rows = result.cmd_tuples
        @logger.info "[DatabaseAnonymizerService] Payment methods table: #{rows} rows anonymized"
        rows
      end

      def handle_unknown_table(table)
        @logger.warn "[DatabaseAnonymizerService] Unknown table: #{table} - skipping"
      end
    end
  end
end
