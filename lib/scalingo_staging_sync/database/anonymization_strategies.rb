# frozen_string_literal: true

require "active_support/core_ext/string/filters"

module ScalingoStagingSync
  module Database
    # Module for anonymization strategies
    # Each strategy defines how to anonymize a specific type of data
    module AnonymizationStrategies
      class << self
        # Registry of custom strategies
        def custom_strategies
          @custom_strategies ||= {}
        end

        # Register a custom anonymization strategy
        # @param name [Symbol] the strategy name
        # @param block [Proc] a block that returns the SQL query
        def register_strategy(name, &block)
          custom_strategies[name] = block
        end

        # Get a strategy by name
        # @param name [Symbol] the strategy name
        # @return [Proc] the strategy block
        def get_strategy(name)
          custom_strategies[name] || builtin_strategies[name]
        end

        # Check if a strategy exists
        # @param name [Symbol] the strategy name
        # @return [Boolean]
        def strategy_exists?(name)
          custom_strategies.key?(name) || builtin_strategies.key?(name)
        end

        private

        def builtin_strategies
          {
            user_anonymization: ->(table, _condition) { user_anonymization_query(table) },
            phone_anonymization: ->(table, _condition) { phone_anonymization_query(table) },
            payment_anonymization: ->(table, _condition) { payment_anonymization_query(table) },
            email_anonymization: ->(table, _condition) { email_anonymization_query(table) },
            address_anonymization: ->(table, _condition) { address_anonymization_query(table) }
          }
        end

        # Built-in strategy: User anonymization
        def user_anonymization_query(table)
          <<~SQL.squish
            UPDATE #{table}
            SET #{user_anonymization_fields}
          SQL
        end

        def user_anonymization_fields
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

        # Built-in strategy: Phone number anonymization
        def phone_anonymization_query(table)
          <<~SQL.squish
            UPDATE #{table}
            SET number = '060' || LPAD(COALESCE(user_id::text, id::text), 7, '0')
          SQL
        end

        # Built-in strategy: Payment method anonymization
        def payment_anonymization_query(table)
          <<~SQL.squish
            UPDATE #{table}
            SET card_last4 = '0000'
          SQL
        end

        # Built-in strategy: Email-only anonymization
        def email_anonymization_query(table)
          <<~SQL.squish
            UPDATE #{table}
            SET email = COALESCE(CAST(id AS TEXT), encode(digest(email::bytea, 'sha256'), 'hex')) || '@demo.example.com'
            WHERE email IS NOT NULL
          SQL
        end

        # Built-in strategy: Address anonymization
        def address_anonymization_query(table)
          <<~SQL.squish
            UPDATE #{table}
            SET address_line1 = '123 Demo Street',
                address_line2 = NULL,
                city = 'Demo City',
                postal_code = '00000'
            WHERE address_line1 IS NOT NULL
          SQL
        end
      end
    end
  end
end
