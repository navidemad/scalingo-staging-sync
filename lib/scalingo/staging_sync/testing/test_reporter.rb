# frozen_string_literal: true

module Scalingo
  module StagingSync
    # Module for test result reporting and formatting
    module TestReporter
      def section_header(title)
        Rails.logger.debug { "\n#{title}" }
        Rails.logger.debug "-" * title.length
      end

      def pass(message)
        Rails.logger.debug { "  ✅ #{message}" }
        @results[message] = :pass
      end

      def fail(message)
        Rails.logger.debug { "  ❌ #{message}" }
        @results[message] = :fail
      end

      def warn(message)
        Rails.logger.debug { "  ⚠️  #{message}" }
        @results[message] = :warn
      end

      def info(message)
        Rails.logger.debug { "  ℹ️  #{message}" }
      end

      def all_tests_passed?
        !failures?
      end

      def display_summary
        @logger.info "[Tester] Generating test summary..."

        print_summary_header
        print_summary_stats
        print_failed_tests if failures?
        print_warnings if warnings?
        print_summary_footer
      end

      private

      def print_summary_header
        Rails.logger.debug { "\n#{'=' * 60}" }
        Rails.logger.debug "TEST SUMMARY"
        Rails.logger.debug "=" * 60
      end

      def print_summary_stats
        total_tests = @results.count
        passed = @results.count { |_, status| status == :pass }
        failed = @results.count { |_, status| status == :fail }
        warnings = @results.count { |_, status| status == :warn }

        Rails.logger.debug "\n📊 Results:"
        Rails.logger.debug { "  ✅ Passed: #{passed}/#{total_tests}" }
        Rails.logger.debug { "  ❌ Failed: #{failed}/#{total_tests}" } if failed > 0
        Rails.logger.debug { "  ⚠️  Warnings: #{warnings}/#{total_tests}" } if warnings > 0
      end

      def print_failed_tests
        Rails.logger.debug "\n❌ Critical issues found:"
        @results.select { |_, status| status == :fail }.each_key do |message|
          Rails.logger.debug "  - #{message}"
        end
      end

      def print_warnings
        Rails.logger.debug "\n⚠️  Warnings:"
        @results.select { |_, status| status == :warn }.each_key do |message|
          Rails.logger.debug "  - #{message}"
        end
      end

      def print_summary_footer
        Rails.logger.debug { "\n#{'=' * 60}" }
        print_test_result_message
        Rails.logger.debug { "#{'=' * 60}\n" }
      end

      def print_test_result_message
        if all_tests_passed?
          print_success_message
        elsif failures?
          print_failure_message
        else
          print_warning_message
        end
      end

      def print_success_message
        Rails.logger.debug "✅ ALL CRITICAL TESTS PASSED - Ready for staging sync!"
        Rails.logger.debug "Run: bundle exec rake staging_sync:sync"
        @logger.info "[Tester] ✅ System ready for staging sync"
      end

      def print_failure_message
        Rails.logger.debug "❌ CRITICAL ISSUES DETECTED - Fix before running sync"
        @logger.error "[Tester] ❌ Critical issues detected - cannot proceed with sync"
      end

      def print_warning_message
        Rails.logger.debug "⚠️  WARNINGS DETECTED - Review before running staging sync"
        Rails.logger.debug "Run with caution: bundle exec rake staging_sync:sync"
        @logger.warn "[Tester] ⚠️  Warnings detected - review before proceeding"
      end

      def failures?
        @results.value?(:fail)
      end

      def warnings?
        @results.value?(:warn)
      end
    end
  end
end
