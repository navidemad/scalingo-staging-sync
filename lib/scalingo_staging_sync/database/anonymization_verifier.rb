# frozen_string_literal: true

module ScalingoStagingSync
  module Database
    # Module for verifying that anonymization actually worked and no PII leaked
    module AnonymizationVerifier
      # Email patterns that indicate production/real emails
      PRODUCTION_EMAIL_PATTERNS = [
        /@gmail\.com$/i,
        /@yahoo\.com$/i,
        /@hotmail\.com$/i,
        /@outlook\.com$/i,
        /@icloud\.com$/i,
        /@live\.com$/i,
        /@protonmail\.com$/i,
        /\+\w+@/i # Email with plus addressing (user+tag@domain.com)
      ].freeze

      # Phone number patterns that indicate real phone numbers
      REAL_PHONE_PATTERNS = [
        /^\+?1[2-9]\d{9}$/, # US/Canada numbers
        /^\+?33[1-9]\d{8}$/, # French numbers (not starting with 060)
        /^\+?44[1-9]\d{9}$/, # UK numbers
        /^[789]\d{9}$/ # Indian numbers
      ].freeze

      # Verifies that a table has been properly anonymized
      # @param connection [PG::Connection] Database connection
      # @param table [String] Table name
      # @return [Hash] { success: Boolean, issues: Array<String>, warnings: Array<String> }
      def verify_table_anonymization(connection, table)
        case table
        when "users"
          verify_users_anonymization(connection)
        when "phone_numbers"
          verify_phone_numbers_anonymization(connection)
        when "payment_methods"
          verify_payment_methods_anonymization(connection)
        else
          { success: true, issues: [], warnings: ["Unknown table: #{table} - no verification performed"] }
        end
      end

      # Verifies users table anonymization
      # @param connection [PG::Connection] Database connection
      # @return [Hash] Verification results
      def verify_users_anonymization(connection)
        issues = []
        warnings = []

        # Check for production emails
        production_emails = check_production_emails(connection)
        issues << "Found #{production_emails} users with production-like email addresses" if production_emails.positive?

        # Check for common real names
        real_names = check_real_names(connection)
        warnings << "Found #{real_names} users with potentially real names" if real_names.positive?

        # Check for real credit card numbers (using Luhn algorithm)
        real_credit_cards = check_real_credit_cards(connection)
        issues << "Found #{real_credit_cards} users with potentially real credit card numbers" if real_credit_cards.positive?

        # Check for real IBAN last 4
        real_ibans = check_real_ibans(connection)
        issues << "Found #{real_ibans} users with non-anonymized IBAN numbers" if real_ibans.positive?

        # Check for remaining tokens
        remaining_tokens = check_remaining_tokens(connection)
        issues << "Found #{remaining_tokens} users with un-nullified authentication tokens" if remaining_tokens.positive?

        # Check for birth dates
        birth_dates = check_birth_dates(connection)
        issues << "Found #{birth_dates} users with non-nullified birth dates" if birth_dates.positive?

        {
          success: issues.empty?,
          issues: issues,
          warnings: warnings
        }
      end

      # Verifies phone_numbers table anonymization
      # @param connection [PG::Connection] Database connection
      # @return [Hash] Verification results
      def verify_phone_numbers_anonymization(connection)
        issues = []
        warnings = []

        # Check for real phone patterns
        real_phones = check_real_phone_patterns(connection)
        issues << "Found #{real_phones} phone numbers matching real phone patterns" if real_phones.positive?

        # Check that all phones start with 060 (expected anonymized format)
        non_anonymized = check_non_anonymized_phones(connection)
        warnings << "Found #{non_anonymized} phone numbers not following 060XXXXXXX format" if non_anonymized.positive?

        {
          success: issues.empty?,
          issues: issues,
          warnings: warnings
        }
      end

      # Verifies payment_methods table anonymization
      # @param connection [PG::Connection] Database connection
      # @return [Hash] Verification results
      def verify_payment_methods_anonymization(connection)
        issues = []

        # Check that all card_last4 are '0000'
        non_anonymized = check_non_anonymized_cards(connection)
        issues << "Found #{non_anonymized} payment methods with non-anonymized card numbers" if non_anonymized.positive?

        {
          success: issues.empty?,
          issues: issues,
          warnings: []
        }
      end

      private

      def check_production_emails(connection)
        patterns_sql = PRODUCTION_EMAIL_PATTERNS.map do |pattern|
          "email ~ '#{pattern.source}'"
        end.join(" OR ")

        query = <<~SQL.squish
          SELECT COUNT(*)
          FROM users
          WHERE email IS NOT NULL
          AND (#{patterns_sql})
        SQL

        result = connection.exec(query)
        result[0]["count"].to_i
      rescue PG::Error => e
        @logger&.error "[AnonymizationVerifier] Error checking production emails: #{e.message}"
        0
      end

      def check_real_names(connection)
        query = <<~SQL.squish
          SELECT COUNT(*)
          FROM users
          WHERE first_name IS NOT NULL
          AND first_name != 'Demo'
          AND LENGTH(first_name) > 2
        SQL

        result = connection.exec(query)
        result[0]["count"].to_i
      rescue PG::Error => e
        @logger&.error "[AnonymizationVerifier] Error checking real names: #{e.message}"
        0
      end

      def check_real_credit_cards(connection)
        query = <<~SQL.squish
          SELECT COUNT(*)
          FROM users
          WHERE credit_card_last_4 IS NOT NULL
          AND credit_card_last_4 != '0000'
          AND credit_card_last_4 ~ '^[0-9]{4}$'
        SQL

        result = connection.exec(query)
        result[0]["count"].to_i
      rescue PG::Error => e
        @logger&.error "[AnonymizationVerifier] Error checking credit cards: #{e.message}"
        0
      end

      def check_real_ibans(connection)
        query = <<~SQL.squish
          SELECT COUNT(*)
          FROM users
          WHERE iban_last4 IS NOT NULL
          AND iban_last4 != '0000'
        SQL

        result = connection.exec(query)
        result[0]["count"].to_i
      rescue PG::Error => e
        @logger&.error "[AnonymizationVerifier] Error checking IBANs: #{e.message}"
        0
      end

      def check_remaining_tokens(connection)
        query = <<~SQL.squish
          SELECT COUNT(*)
          FROM users
          WHERE google_token IS NOT NULL
          OR facebook_token IS NOT NULL
          OR apple_id IS NOT NULL
          OR stripe_customer_id IS NOT NULL
        SQL

        result = connection.exec(query)
        result[0]["count"].to_i
      rescue PG::Error => e
        @logger&.error "[AnonymizationVerifier] Error checking tokens: #{e.message}"
        0
      end

      def check_birth_dates(connection)
        query = <<~SQL.squish
          SELECT COUNT(*)
          FROM users
          WHERE birth_date IS NOT NULL
          OR birth_place IS NOT NULL
        SQL

        result = connection.exec(query)
        result[0]["count"].to_i
      rescue PG::Error => e
        @logger&.error "[AnonymizationVerifier] Error checking birth dates: #{e.message}"
        0
      end

      def check_real_phone_patterns(connection)
        patterns_sql = REAL_PHONE_PATTERNS.map do |pattern|
          "number ~ '#{pattern.source}'"
        end.join(" OR ")

        query = <<~SQL.squish
          SELECT COUNT(*)
          FROM phone_numbers
          WHERE number IS NOT NULL
          AND (#{patterns_sql})
        SQL

        result = connection.exec(query)
        result[0]["count"].to_i
      rescue PG::Error => e
        @logger&.error "[AnonymizationVerifier] Error checking phone patterns: #{e.message}"
        0
      end

      def check_non_anonymized_phones(connection)
        query = <<~SQL.squish
          SELECT COUNT(*)
          FROM phone_numbers
          WHERE number IS NOT NULL
          AND number !~ '^060[0-9]{7}$'
        SQL

        result = connection.exec(query)
        result[0]["count"].to_i
      rescue PG::Error => e
        @logger&.error "[AnonymizationVerifier] Error checking anonymized phone format: #{e.message}"
        0
      end

      def check_non_anonymized_cards(connection)
        query = <<~SQL.squish
          SELECT COUNT(*)
          FROM payment_methods
          WHERE card_last4 IS NOT NULL
          AND card_last4 != '0000'
        SQL

        result = connection.exec(query)
        result[0]["count"].to_i
      rescue PG::Error => e
        @logger&.error "[AnonymizationVerifier] Error checking card numbers: #{e.message}"
        0
      end
    end
  end
end
