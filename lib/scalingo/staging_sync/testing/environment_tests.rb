# frozen_string_literal: true

module Scalingo
  module StagingSync
    # Module for environment and security testing
    module EnvironmentTests
      def test_security_guards
        @logger.info "[Tester] Testing security guards..."
        section_header("Security Guards")

        test_rails_environment
        test_app_environment_variable
      end

      def test_environment_variables
        @logger.info "[Tester] Testing environment variables..."
        section_header("Environment Variables")

        test_database_urls
        test_scalingo_api_token
      end

      private

      def test_rails_environment
        if Rails.env.production?
          @logger.critical "[Tester] CRITICAL: Rails.env is PRODUCTION!"
          Rails.logger.debug "  ⚠️  NEVER run staging sync in production environment!"
          @slack_notifier.notify_warning("🔴 CRITICAL: Production environment detected!", context: "[Tester]")
          raise "Rails.env is PRODUCTION - THIS IS CRITICAL!"
        else
          pass "Rails.env: #{Rails.env} (safe)"
          @logger.info "[Tester] Rails environment safe: #{Rails.env}"
        end
      end

      def test_app_environment_variable
        if ENV["APP"].present?
          if ENV["APP"].include?("prod")
            @logger.error "[Tester] APP variable contains 'prod': #{ENV['APP']}"
            raise "APP contains 'prod': #{ENV['APP']}"
          else
            pass "APP: #{ENV['APP']} (safe)"
            @logger.info "[Tester] APP variable safe: #{ENV['APP']}"
          end
        else
          info "  APP: not set"
          @logger.debug "[Tester] APP environment variable not set"
        end
      end

      def test_database_urls
        database_url = ENV.fetch("DATABASE_URL", nil)
        scalingo_url = ENV.fetch("SCALINGO_POSTGRESQL_URL", nil)

        if database_url.present?
          pass "DATABASE_URL is set"
          test_database_url_safety(database_url)
        elsif scalingo_url.present?
          pass "SCALINGO_POSTGRESQL_URL is set (fallback)"
          test_database_url_safety(scalingo_url)
        else
          raise "No database URL found (DATABASE_URL or SCALINGO_POSTGRESQL_URL)"
        end
      end

      def test_scalingo_api_token
        if ENV["SCALINGO_API_TOKEN"].present?
          pass "SCALINGO_API_TOKEN is set"
          @logger.info "[Tester] Scalingo API token configured"
        else
          warn "SCALINGO_API_TOKEN not set (may be needed for backup downloads)"
          @logger.warn "[Tester] Scalingo API token not configured - backup downloads may fail"
        end
      end

      def test_database_url_safety(url)
        uri = URI.parse(url)
        raise "  ⚠️  Database name contains 'prod': #{uri.path}" if uri.path&.include?("prod")

        info "  Database: #{uri.path&.delete('/') || 'unknown'}"
      rescue StandardError => e
        warn "  Could not parse database URL: #{e.message}"
      end
    end
  end
end
