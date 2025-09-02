# frozen_string_literal: true

require "tmpdir"
require "logger"

module Scalingo
  module StagingSync
    class Configuration
      attr_accessor :clone_source_scalingo_app_name,
                    :slack_webhook_url,
                    :slack_channel,
                    :slack_enabled,
                    :exclude_tables,
                    :parallel_connections,
                    :logger,
                    :temp_dir,
                    :seeds_file_path

      # Default values
      def initialize
        @clone_source_scalingo_app_name = "your-production-app"
        @slack_webhook_url = nil
        @slack_channel = nil
        @slack_enabled = false
        @exclude_tables = []
        @parallel_connections = 3
        @logger = defined?(Rails) ? Rails.logger : Logger.new($stdout)
        @temp_dir = defined?(Rails) ? Rails.root.join("tmp") : Dir.tmpdir
        @seeds_file_path = nil
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
end
