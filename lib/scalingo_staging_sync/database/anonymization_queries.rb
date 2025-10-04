# frozen_string_literal: true

module ScalingoStagingSync
  module Database
    # Module containing SQL queries for data anonymization
    module AnonymizationQueries
      def users_anonymization_query
        <<~SQL.squish
          UPDATE users
          SET #{users_anonymization_fields}
        SQL
      end

      private

      def users_anonymization_fields
        [user_identity_fields, user_address_fields, user_token_fields].join(", ")
      end

      def user_identity_fields
        <<~FIELDS.squish
          email = 'user' || id || '@demo.yespark.fr',
          email_md5 = MD5(email),
          first_name = 'Demo',
          last_name = 'User' || id,
          full_name = first_name || ' ' || last_name,
          credit_card_last_4 = '0000',
          iban_last4 = '0000',
          stripe_customer_id = NULL
        FIELDS
      end

      def user_address_fields
        <<~FIELDS.squish
          address_line1 = '8 rue du sentier',
          address_line2 = NULL,
          city = 'Paris',
          postal_code = '75002',
          birth_date = NULL,
          birth_place = NULL
        FIELDS
      end

      def user_token_fields
        <<~FIELDS.squish
          billing_extra = NULL,
          zendesk_user_id = NULL
        FIELDS
      end

      def phone_numbers_anonymization_query
        <<~SQL.squish
          UPDATE phone_numbers
          SET number = '060' || LPAD(COALESCE(user_id::text, id::text), 7, '0')
        SQL
      end

      def payment_methods_anonymization_query
        <<~SQL.squish
          UPDATE payment_methods
          SET card_last4 = '0000'
        SQL
      end

      # Verification Queries
      # These queries help verify that anonymization succeeded

      def users_verification_query
        <<~SQL.squish
          SELECT
            COUNT(*) FILTER (WHERE email ~ '@(gmail|yahoo|hotmail|outlook|icloud).com$') as production_emails,
            COUNT(*) FILTER (WHERE first_name != 'Demo' AND first_name IS NOT NULL) as real_names,
            COUNT(*) FILTER (WHERE credit_card_last_4 != '0000' AND credit_card_last_4 IS NOT NULL) as real_credit_cards,
            COUNT(*) FILTER (WHERE iban_last4 != '0000' AND iban_last4 IS NOT NULL) as real_ibans,
            COUNT(*) FILTER (WHERE stripe_customer_id IS NOT NULL) as remaining_tokens,
            COUNT(*) FILTER (WHERE birth_date IS NOT NULL OR birth_place IS NOT NULL) as birth_dates,
            COUNT(*) as total_rows
          FROM users
        SQL
      end

      def phone_numbers_verification_query
        <<~SQL.squish
          SELECT
            COUNT(*) FILTER (WHERE number ~ '^\\+?1[2-9]\\d{9}$'
                             OR number ~ '^\\+?33[1-9]\\d{8}$'
                             OR number ~ '^\\+?44[1-9]\\d{9}$'
                             OR number ~ '^[789]\\d{9}$') as real_phones,
            COUNT(*) FILTER (WHERE number !~ '^060[0-9]{7}$' AND number IS NOT NULL) as non_anonymized_format,
            COUNT(*) as total_rows
          FROM phone_numbers
        SQL
      end

      def payment_methods_verification_query
        <<~SQL.squish
          SELECT
            COUNT(*) FILTER (WHERE card_last4 != '0000' AND card_last4 IS NOT NULL) as non_anonymized_cards,
            COUNT(*) as total_rows
          FROM payment_methods
        SQL
      end

      # Generic verification query that can be customized
      def verify_no_real_pii(table, pii_columns)
        column_checks = pii_columns.map do |col|
          "COUNT(*) FILTER (WHERE #{col} IS NOT NULL) as #{col}_count"
        end.join(", ")

        <<~SQL.squish
          SELECT
            #{column_checks},
            COUNT(*) as total_rows
          FROM #{table}
        SQL
      end
    end
  end
end
