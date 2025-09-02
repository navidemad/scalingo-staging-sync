# frozen_string_literal: true

module Scalingo
  module StagingSync
    # Module containing SQL queries for data anonymization
    module AnonymizationQueries
      def users_anonymization_query
        <<~SQL.squish
          UPDATE users
          SET #{users_anonymization_fields}
          WHERE anonymized_at IS NULL
        SQL
      end

      private

      def users_anonymization_fields
        [user_identity_fields, user_address_fields, user_token_fields].join(", ")
      end

      def user_identity_fields
        <<~FIELDS.squish
          email = SUBSTRING(encode(digest(email::bytea, 'sha256'), 'hex'), 1, 8) || '@demo.yespark.fr',
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
          google_token = NULL,
          facebook_token = NULL,
          apple_id = NULL,
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
    end
  end
end
