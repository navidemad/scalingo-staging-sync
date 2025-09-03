# frozen_string_literal: true

module ScalingoStagingSync
  module Testing
    # Module for configuration testing
    module ConfigTests
      def test_configuration
        @logger.info "[Tester] Testing configuration..."
        section_header("Configuration")

        @config = ScalingoStagingSync.configuration
        validate_config_values
      rescue StandardError => e
        @logger.error "[Tester] Failed to validate configuration: #{e.message}"
        raise "Error validating configuration: #{e.message}"
      end

      private

      def validate_config_values
        pass "Configuration loaded"
        @logger.info "[Tester] Configuration loaded successfully"

        # Check required configuration
        validate_required_config

        # Check optional configuration
        log_optional_config
      end

      def validate_required_config
        # Clone source app name
        raise "Missing config: clone_source_scalingo_app_name" unless @config.clone_source_scalingo_app_name.present?

        info "  Clone source app: #{@config.clone_source_scalingo_app_name}"

        # Target app (from ENV)
        begin
          target = @config.target_app
          info "  Target app: #{target}"
        rescue ArgumentError => e
          @logger.warn "[Tester] Target app not available: #{e.message}"
          warn "  Target app: Not set (ENV['APP'] required on Scalingo)"
        end
      end

      def log_optional_config
        log_slack_config
        log_excluded_tables
        log_other_settings
      end

      def log_slack_config
        if @config.slack_enabled
          info "  Slack notifications: ✅ Enabled"
          info "    Channel: #{@config.slack_channel}" if @config.slack_channel.present?
        else
          info "  Slack notifications: ❌ Disabled"
        end
      end

      def log_excluded_tables
        return unless @config.exclude_tables.present?

        info "  Excluded tables: #{@config.exclude_tables.size} tables"
        @config.exclude_tables.each { |table| info "    - #{table}" }
      end

      def log_other_settings
        info "  Parallel connections: #{@config.parallel_connections}"
        info "  PostGIS enabled: #{@config.postgis}"

        return unless @config.seeds_file_path.present?

        info "  Seeds file: #{@config.seeds_file_path}"
      end
    end
  end
end
