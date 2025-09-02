# frozen_string_literal: true

require_relative "test_reporter"
require_relative "config_tests"
require_relative "environment_tests"
require_relative "system_tests"

module Scalingo
  module StagingSync
    class Tester
      include TestReporter
      include ConfigTests
      include EnvironmentTests
      include SystemTests

      def initialize(logger: Rails.logger)
        @logger = logger
        @results = {}
        @config_file = Rails.root.join("config/scalingo_staging_sync.yml")
        @slack_notifier = Scalingo::StagingSync::SlackNotificationService.new(logger: logger)
      end

      def run_tests!
        @logger.info "[Tester] Starting demo database sync configuration tests..."
        @slack_notifier.notify_step("🧪 Starting configuration tests", context: "[Tester]")

        print_test_header
        run_all_tests
        display_summary
        report_final_status
      end

      private

      def print_test_header
        Rails.logger.debug { "\n#{'=' * 60}" }
        Rails.logger.debug "DEMO DATABASE SYNC CONFIGURATION TEST"
        Rails.logger.debug "=" * 60
      end

      def run_all_tests
        @logger.info "[Tester] Running test suite..."
        test_configuration_file
        test_security_guards
        test_environment_variables
        test_required_tools
        test_database_connectivity
        test_slack_integration
        test_permissions
      end

      def report_final_status
        result = all_tests_passed?

        if result
          @logger.info "[Tester] ✅ All tests passed successfully"
          @slack_notifier.notify_step("✅ Configuration tests passed", context: "[Tester]")
        else
          @logger.error "[Tester] ❌ Tests failed - see summary for details"
          @slack_notifier.notify_warning("Configuration tests failed - check logs", context: "[Tester]")
        end

        result
      end

      def test_slack_integration
        @logger.info "[Tester] Testing Slack integration..."
        section_header("Slack Integration")

        if defined?(SlackNotificationService)
          pass "SlackNotificationService class is loaded"
          @logger.info "[Tester] SlackNotificationService module is available"
          test_slack_methods
        else
          warn "SlackNotifier not defined - notifications will be skipped"
          @logger.warn "[Tester] SlackNotifier not available - Slack notifications disabled"
        end
      end

      def test_slack_methods
        required_methods = %i[notify_step notify_success notify_failure]
        missing_methods = required_methods.reject { |m| SlackNotificationService.new.respond_to?(m) }

        if missing_methods.empty?
          pass "All required Slack methods available"
          @logger.info "[Tester] All required Slack notification methods available"
        else
          @logger.error "[Tester] Missing Slack methods: #{missing_methods.join(', ')}"
          raise "Missing Slack methods: #{missing_methods.join(', ')}"
        end
      end
    end
  end
end
