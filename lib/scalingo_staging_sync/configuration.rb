# frozen_string_literal: true

require "active_support/configurable"
require "tmpdir"
require "logger"
require "pathname"

module ScalingoStagingSync
  class Configuration
    include ActiveSupport::Configurable

    config_accessor :clone_source_scalingo_app_name, default: "your-production-app"
    config_accessor :slack_webhook_url, default: nil
    config_accessor :slack_channel, default: nil
    config_accessor :slack_enabled, default: false
    config_accessor :exclude_tables, default: []
    config_accessor :parallel_connections, default: 3
    config_accessor :seeds_file_path, default: nil
    config_accessor :postgis, default: false

    # Transaction and error handling configuration
    config_accessor :anonymization_rollback_on_error, default: true
    config_accessor :anonymization_retry_attempts, default: 3
    config_accessor :anonymization_retry_delay, default: 1.0

    # Anonymization verification configuration
    config_accessor :verify_anonymization, default: true
    config_accessor :fail_on_verification_error, default: true
    config_accessor :pii_detection_patterns, default: nil # Uses default patterns if nil
    config_accessor :anonymization_audit_file, default: nil # Path to save audit report
    config_accessor :run_pii_scan, default: true # Whether to scan for unanonymized PII columns

    # Anonymization configuration
    # Array of hashes defining tables to anonymize and their strategies
    # Each hash can contain:
    #   - table: (required) table name as string
    #   - strategy: (optional) strategy name as symbol (:user_anonymization, :phone_anonymization, etc.)
    #   - query: (optional) custom SQL query string (alternative to strategy)
    #   - condition: (optional) WHERE clause condition as string
    #   - translation: (optional) French translation for Slack notifications
    #
    # Example:
    #   config.anonymization_tables = [
    #     { table: 'users', strategy: :user_anonymization, translation: 'utilisateurs' },
    #     { table: 'phone_numbers', strategy: :phone_anonymization, translation: 'téléphones' },
    #     { table: 'payment_methods', strategy: :payment_anonymization, translation: 'moyens de paiement' },
    #     { table: 'emails', strategy: :email_anonymization },
    #     { table: 'addresses', strategy: :address_anonymization },
    #     { table: 'custom_table', query: 'UPDATE custom_table SET field = NULL' }
    #   ]
    #
    # If not configured, defaults to hardcoded legacy tables (users, phone_numbers, payment_methods)
    # with a deprecation warning.
    config_accessor :anonymization_tables, default: []

    # Production protection settings
    config_accessor :production_hostname_patterns,
                    default: [
                      /prod/i,
                      /production/i
                    ]
    config_accessor :production_app_name_patterns,
                    default: [
                      /prod/i,
                      /production/i
                    ]
    config_accessor :require_confirmation, default: false
    config_accessor :dry_run, default: false

    # Custom accessors with smart defaults
    attr_writer :logger, :temp_dir

    def logger
      @logger || (defined?(Rails) ? Rails.logger : Logger.new($stdout))
    end

    def temp_dir
      value = @temp_dir || (defined?(Rails) ? Rails.root.join("tmp") : Dir.tmpdir)
      value.is_a?(String) ? Pathname.new(value) : value
    end

    def target_app
      ENV.fetch("APP") do
        raise ArgumentError,
              "ENV['APP'] is required but not set. " \
              "This should be automatically available on Scalingo instances."
      end
    end
  end
end
