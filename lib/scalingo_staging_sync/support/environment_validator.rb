# frozen_string_literal: true

module ScalingoStagingSync
  module Support
    # Module for environment validation and safety checks
    module EnvironmentValidator
      def validate_environment!
        @logger.info "[Coordinator] Validating environment and safety checks..."

        validate_rails_environment
        validate_app_name
        validate_database_url

        @logger.info "[Coordinator] All safety checks passed - proceeding with sync"
      end

      private

      def validate_rails_environment
        if Rails.env.production?
          @logger.error "[Coordinator] CRITICAL: Attempted to run in production environment!"
          raise "CRITICAL: Cannot run in production!"
        end
        @logger.info "[Coordinator] ✓ Rails environment check passed: #{Rails.env}"
      end

      def validate_app_name
        if ENV["APP"]&.include?("prod")
          @logger.error "[Coordinator] App name contains 'prod': #{ENV.fetch('APP', nil)}"
          raise "App name contains 'prod' - stopping for safety"
        end
        @logger.info "[Coordinator] ✓ App name check passed: #{ENV['APP'] || 'not set'}"
      end

      def validate_database_url
        database_url = ENV["DATABASE_URL"] || ENV.fetch("SCALINGO_POSTGRESQL_URL", nil)
        unless database_url
          @logger.error "[Coordinator] No database URL found in environment"
          raise "No DATABASE_URL found"
        end

        @database_url = database_url
        @logger.info "[Coordinator] ✓ Database URL configured"
      end
    end
  end
end
