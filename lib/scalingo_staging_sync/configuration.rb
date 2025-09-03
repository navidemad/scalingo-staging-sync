# frozen_string_literal: true

require "active_support/configurable"
require "tmpdir"
require "logger"

module ScalingoStagingSync
  class Configuration
    include ActiveSupport::Configurable

    config_accessor :clone_source_scalingo_app_name, default: "your-production-app"
    config_accessor :slack_webhook_url, default: nil
    config_accessor :slack_channel, default: nil
    config_accessor :slack_enabled, default: false
    config_accessor :exclude_tables, default: []
    config_accessor :parallel_connections, default: 3
    config_accessor :logger, default: nil
    config_accessor :temp_dir, default: nil
    config_accessor :seeds_file_path, default: nil
    config_accessor :postgis, default: false

    def logger
      @logger ||= Rails.logger
    end

    def temp_dir
      @temp_dir ||= Rails.root.join("tmp")
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
