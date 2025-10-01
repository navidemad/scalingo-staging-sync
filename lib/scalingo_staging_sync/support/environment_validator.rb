# frozen_string_literal: true

require "uri"

module ScalingoStagingSync
  module Support
    # Module for environment validation and safety checks
    module EnvironmentValidator
      class ProductionEnvironmentError < StandardError; end

      def validate_environment!
        @logger.info "[Coordinator] ═══════════════════════════════════════════════════════"
        @logger.info "[Coordinator] Starting comprehensive environment validation..."
        @logger.info "[Coordinator] ═══════════════════════════════════════════════════════"

        log_environment_details

        # Collect all failed checks
        failed_checks = []

        failed_checks << validate_rails_environment
        failed_checks << validate_app_name
        failed_checks << validate_scalingo_postgresql_url
        @database_url = validate_database_url(failed_checks)

        # Remove nil values (successful checks)
        failed_checks.compact!

        handle_failed_checks(failed_checks) if failed_checks.any?

        # Interactive confirmation if required and not in CI
        request_confirmation if @config.require_confirmation && !ci_environment?

        log_dry_run_mode if @config.dry_run

        @logger.info "[Coordinator] ═══════════════════════════════════════════════════════"
        @logger.info "[Coordinator] ✅ All safety checks passed - proceeding with sync"
        @logger.info "[Coordinator] ═══════════════════════════════════════════════════════"
      end

      private

      def log_environment_details
        @logger.info "[Coordinator] Environment Details:"
        @logger.info "[Coordinator]   - Rails Environment: #{Rails.env}"
        @logger.info "[Coordinator]   - APP (Target): #{ENV['APP'] || 'not set'}"
        @logger.info "[Coordinator]   - Source App: #{@source_app}"
        @logger.info "[Coordinator]   - CI Environment: #{ci_environment?}"
        @logger.info "[Coordinator]   - Dry Run Mode: #{@config.dry_run}"
        @logger.info "[Coordinator]   - Require Confirmation: #{@config.require_confirmation}"
        @logger.info "[Coordinator] ---------------------------------------------------------------"
      end

      def validate_rails_environment
        if Rails.env.production?
          @logger.error "[Coordinator] ❌ CRITICAL: Rails environment is set to PRODUCTION!"
          return {
            check: "Rails Environment",
            reason: "Rails.env is 'production'",
            value: Rails.env.to_s,
            remediation: "This operation is BLOCKED in production environments. " \
                         "If this is intentional, change Rails.env to 'staging' or another non-production environment."
          }
        end
        @logger.info "[Coordinator] ✓ Rails environment check passed: #{Rails.env}"
        nil
      end

      def validate_app_name
        app_name = ENV.fetch("APP", nil)
        return nil unless app_name

        patterns = @config.production_app_name_patterns

        patterns.each do |pattern|
          next unless pattern.match?(app_name)

          @logger.error "[Coordinator] ❌ CRITICAL: APP name '#{app_name}' matches production pattern: #{pattern.inspect}"
          return {
            check: "APP Environment Variable",
            reason: "APP name matches production pattern: #{pattern.inspect}",
            value: app_name,
            remediation: "The APP environment variable '#{app_name}' appears to be a production app. " \
                         "To override this check, update the 'production_app_name_patterns' configuration."
          }
        end

        @logger.info "[Coordinator] ✓ APP name check passed: #{app_name}"
        nil
      end

      def validate_scalingo_postgresql_url
        scalingo_url = ENV.fetch("SCALINGO_POSTGRESQL_URL", nil)
        return nil unless scalingo_url

        hostname = extract_hostname_from_url(scalingo_url)
        return nil unless hostname

        patterns = @config.production_hostname_patterns

        patterns.each do |pattern|
          next unless pattern.match?(hostname)

          @logger.error "[Coordinator] ❌ CRITICAL: SCALINGO_POSTGRESQL_URL hostname '#{hostname}' matches production pattern: #{pattern.inspect}"
          return {
            check: "SCALINGO_POSTGRESQL_URL Hostname",
            reason: "Database hostname matches production pattern: #{pattern.inspect}",
            value: hostname,
            remediation: "The SCALINGO_POSTGRESQL_URL hostname '#{hostname}' appears to point to a production database. " \
                         "To override this check, update the 'production_hostname_patterns' configuration."
          }
        end

        @logger.info "[Coordinator] ✓ SCALINGO_POSTGRESQL_URL hostname check passed: #{hostname}"
        nil
      end

      def validate_database_url(failed_checks)
        database_url = ENV["DATABASE_URL"] || ENV.fetch("SCALINGO_POSTGRESQL_URL", nil)

        unless database_url
          @logger.error "[Coordinator] ❌ CRITICAL: No database URL found in environment"
          failed_checks << {
            check: "Database URL",
            reason: "Neither DATABASE_URL nor SCALINGO_POSTGRESQL_URL is set",
            value: "not set",
            remediation: "Set DATABASE_URL or SCALINGO_POSTGRESQL_URL environment variable to point to your staging database."
          }
          return nil
        end

        hostname = extract_hostname_from_url(database_url)
        if hostname
          patterns = @config.production_hostname_patterns

          patterns.each do |pattern|
            next unless pattern.match?(hostname)

            @logger.error "[Coordinator] ❌ CRITICAL: DATABASE_URL hostname '#{hostname}' matches production pattern: #{pattern.inspect}"
            failed_checks << {
              check: "DATABASE_URL Hostname",
              reason: "Database hostname matches production pattern: #{pattern.inspect}",
              value: hostname,
              remediation: "The DATABASE_URL hostname '#{hostname}' appears to point to a production database. " \
                           "To override this check, update the 'production_hostname_patterns' configuration."
            }
          end
        end

        @logger.info "[Coordinator] ✓ Database URL configured"
        database_url
      end

      def extract_hostname_from_url(url)
        uri = URI.parse(url)
        uri.host
      rescue URI::InvalidURIError => e
        @logger.warn "[Coordinator] Could not parse URL for hostname validation: #{e.message}"
        nil
      end

      def handle_failed_checks(failed_checks)
        @logger.error "[Coordinator] ═══════════════════════════════════════════════════════"
        @logger.error "[Coordinator] ❌ PRODUCTION ENVIRONMENT DETECTED - OPERATION BLOCKED"
        @logger.error "[Coordinator] ═══════════════════════════════════════════════════════"
        @logger.error "[Coordinator]"
        @logger.error "[Coordinator] #{failed_checks.size} safety check(s) failed:"
        @logger.error "[Coordinator]"

        failed_checks.each_with_index do |check, index|
          @logger.error "[Coordinator] #{index + 1}. #{check[:check]}"
          @logger.error "[Coordinator]    Reason: #{check[:reason]}"
          @logger.error "[Coordinator]    Value: #{check[:value]}"
          @logger.error "[Coordinator]    Remediation: #{check[:remediation]}"
          @logger.error "[Coordinator]"
        end

        @logger.error "[Coordinator] ═══════════════════════════════════════════════════════"
        @logger.error "[Coordinator] For security reasons, this operation cannot proceed."
        @logger.error "[Coordinator] ═══════════════════════════════════════════════════════"

        error_summary = failed_checks.map { |c| c[:check] }.join(", ")
        raise ProductionEnvironmentError,
              "CRITICAL: Production environment detected. Failed checks: #{error_summary}. " \
              "This operation is blocked for safety. Review the logs above for detailed remediation steps."
      end

      def request_confirmation
        @logger.warn "[Coordinator] ⚠️  Interactive confirmation required"
        @logger.warn "[Coordinator] This operation will CLONE the production database from '#{@source_app}'"
        @logger.warn "[Coordinator] and OVERWRITE the database for '#{@target_app}'"
        @logger.warn "[Coordinator]"
        @logger.warn "[Coordinator] To proceed, type the target app name exactly: #{@target_app}"
        @logger.warn "[Coordinator]"

        print "[CONFIRMATION REQUIRED] Type '#{@target_app}' to continue: "
        $stdout.flush

        # Read user input
        user_input = $stdin.gets&.chomp

        unless user_input == @target_app
          @logger.error "[Coordinator] ❌ Confirmation failed. Expected '#{@target_app}', got '#{user_input}'"
          raise ProductionEnvironmentError,
                "Operation cancelled: User confirmation failed. Expected '#{@target_app}', got '#{user_input || 'nothing'}'"
        end

        @logger.info "[Coordinator] ✓ User confirmation received"
      end

      def ci_environment?
        %w[true 1].include?(ENV.fetch("CI", nil)) || %w[true 1].include?(ENV.fetch("CONTINUOUS_INTEGRATION", nil))
      end

      def log_dry_run_mode
        @logger.warn "[Coordinator] ═══════════════════════════════════════════════════════"
        @logger.warn "[Coordinator] 🔍 DRY RUN MODE ENABLED"
        @logger.warn "[Coordinator] ═══════════════════════════════════════════════════════"
        @logger.warn "[Coordinator] All operations will be logged but NOT executed."
        @logger.warn "[Coordinator] This is a simulation to verify configuration."
        @logger.warn "[Coordinator] ═══════════════════════════════════════════════════════"
      end
    end
  end
end
