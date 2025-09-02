# frozen_string_literal: true

require "tmpdir"
require "logger"

module Scalingo
  module Database
    module Cloner
      class Configuration
        attr_accessor :source_app,
                      :slack_channel,
                      :slack_enabled,
                      :exclude_tables,
                      :parallel_connections,
                      :logger,
                      :temp_dir,
                      :seeds_file_path
        attr_writer :slack_webhook_url

        def initialize
          # Default values
          @source_app = "yespark-demo"
          @slack_webhook_url = nil # Will try Rails.credentials or ENV["SLACK_WEBHOOK_URL"]
          @slack_channel = "#tmp-demo-database-sync"
          @slack_enabled = true
          @exclude_tables = []
          @parallel_connections = 3
          @logger = defined?(Rails) ? Rails.logger : Logger.new($stdout)
          @temp_dir = defined?(Rails) ? Rails.root.join("tmp") : Dir.tmpdir
          @seeds_file_path = defined?(Rails) ? Rails.root.join("db/seeds/staging.rb") : nil
        end

        def slack_webhook_url
          @slack_webhook_url || fetch_webhook_from_credentials || ENV.fetch("SLACK_WEBHOOK_URL", nil)
        end

        def target_app
          ENV.fetch("APP") do
            raise ArgumentError,
                  "ENV['APP'] is required but not set. " \
                  "This should be automatically available on Scalingo instances."
          end
        end

        private

        def fetch_webhook_from_credentials
          return nil unless defined?(Rails)

          Rails.application.credentials.dig(:slack, :webhook_url)
        rescue StandardError
          nil
        end
      end
    end
  end
end
