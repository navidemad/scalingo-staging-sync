# frozen_string_literal: true

# Configure the Scalingo Staging Sync
#
# This gem syncs and anonymizes Scalingo production databases for safe use in staging/demo environments.
#
# For more information, see: https://github.com/navidemad/scalingo-staging-sync

ScalingoStagingSync.configure do |config|
  # Required: Scalingo app to clone from (app name)
  config.clone_source_scalingo_app_name = "your-production-app"

  # Optional: Slack integration for notifications
  # config.slack_enabled = true
  # config.slack_channel = "#deployments"
  # config.slack_webhook_url = "https://hooks.slack.com/services/..."

  # Optional: Tables to exclude from cloning
  # config.exclude_tables = %w[
  #   temp_data
  #   audit_logs
  #   active_storage_blobs
  # ]

  # Optional: Number of parallel database connections for anonymization (default: 3)
  # config.parallel_connections = 3

  # Optional: Path to seeds file to run after cloning (no default - must be explicitly set)
  # config.seeds_file_path = Rails.root.join("db/seeds/staging.rb")

  # Optional: Whether to use PostGIS extension (default: false)
  # Set to true if your database uses PostGIS
  # config.postgis = true

  # Optional: Anonymization configuration
  # Configure which tables to anonymize and how to anonymize them
  # If not configured, defaults to legacy tables (users, phone_numbers, payment_methods) with deprecation warning
  #
  # Each table entry can have:
  #   - table: (required) table name as string
  #   - strategy: (optional) built-in strategy name as symbol
  #   - query: (optional) custom SQL query string (alternative to strategy)
  #   - condition: (optional) additional WHERE clause condition
  #   - translation: (optional) French translation for Slack notifications
  #
  # Built-in strategies:
  #   - :user_anonymization - Anonymize user tables (email, names, addresses, tokens)
  #   - :phone_anonymization - Anonymize phone numbers
  #   - :payment_anonymization - Anonymize payment method details
  #   - :email_anonymization - Anonymize only email addresses
  #   - :address_anonymization - Anonymize only address fields
  #
  # Example configurations:
  #
  # config.anonymization_tables = [
  #   # Using built-in strategies
  #   { table: "users", strategy: :user_anonymization, translation: "utilisateurs" },
  #   { table: "phone_numbers", strategy: :phone_anonymization, translation: "téléphones" },
  #   { table: "payment_methods", strategy: :payment_anonymization, translation: "moyens de paiement" },
  #
  #   # Using built-in strategies with conditions
  #   { table: "old_users", strategy: :user_anonymization, condition: "created_at < NOW() - INTERVAL '1 year'" },
  #
  #   # Using custom SQL queries
  #   { table: "custom_table", query: "UPDATE custom_table SET field = NULL WHERE sensitive = true" },
  #   { table: "api_keys", query: "UPDATE api_keys SET key = MD5(RANDOM()::text)" },
  #
  #   # Combine strategies with additional tables
  #   { table: "emails", strategy: :email_anonymization },
  #   { table: "addresses", strategy: :address_anonymization }
  # ]
  #
  # To register custom strategies in your application:
  #
  # ScalingoStagingSync::Database::AnonymizationStrategies.register_strategy(:my_custom_strategy) do |table, condition|
  #   <<~SQL.squish
  #     UPDATE #{table}
  #     SET custom_field = 'anonymized'
  #     WHERE sensitive = true
  #   SQL
  # end
end
