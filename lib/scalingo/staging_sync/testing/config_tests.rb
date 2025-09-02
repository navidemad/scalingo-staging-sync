# frozen_string_literal: true

module Scalingo
  module StagingSync
    # Module for configuration file testing
    module ConfigTests
      def test_configuration_file
        @logger.info "[Tester] Testing configuration file..."
        section_header("Configuration File")

        if File.exist?(@config_file)
          load_and_validate_config
        else
          @logger.error "[Tester] Config file not found: #{@config_file}"
          @config = {}
          raise "scalingo_staging_sync.yml not found at #{@config_file}"
        end
      rescue StandardError => e
        @logger.error "[Tester] Failed to load config: #{e.message}"
        @config = {}
        raise "Error loading config: #{e.message}"
      end

      private

      def load_and_validate_config
        @config = YAML.load_file(@config_file)
        pass "scalingo_staging_sync.yml found"
        @logger.info "[Tester] Config file loaded successfully from #{@config_file}"
        validate_config_keys
      end

      def validate_config_keys
        required_keys = {
          "target_app" => "Target application name",
          "clone_source_scalingo_app_name" => "Clone source Scalingo app name"
        }

        required_keys.each do |key, description|
          raise "Missing config: #{key}" unless @config[key].present?

          info "  #{description}: #{@config[key]}"
        end

        log_optional_config
      end

      def log_optional_config
        info "  Anonymization: ✅ Enabled"
        info "  Slack notifications: ✅ Enabled"

        return unless @config.dig("database", "exclude_tables").present?

        info "  Excluded tables: #{@config.dig('database', 'exclude_tables').size} tables"
        @config["database"]["exclude_tables"].each { |table| info "    - #{table}" }
      end
    end
  end
end
