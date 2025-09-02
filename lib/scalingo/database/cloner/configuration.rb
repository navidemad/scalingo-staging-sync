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
        attr_writer :target_app, :slack_webhook_url

        def initialize
          # Default values
          @source_app = "yespark-demo"
          @target_app = nil # Will use ENV["APP"] by default
          @slack_webhook_url = nil # Will try Rails.credentials or ENV["SLACK_WEBHOOK_URL"]
          @slack_channel = "#tmp-demo-database-sync"
          @slack_enabled = true
          @exclude_tables = default_exclude_tables
          @parallel_connections = 3
          @logger = defined?(Rails) ? Rails.logger : Logger.new($stdout)
          @temp_dir = defined?(Rails) ? Rails.root.join("tmp") : Dir.tmpdir
          @seeds_file_path = defined?(Rails) ? Rails.root.join("db/seeds/staging.rb") : nil
        end

        def slack_webhook_url
          @slack_webhook_url || fetch_webhook_from_credentials || ENV.fetch("SLACK_WEBHOOK_URL", nil)
        end

        def target_app
          ENV["APP"] || @target_app
        end

        private

        def fetch_webhook_from_credentials
          return nil unless defined?(Rails)

          Rails.application.credentials.dig(:slack, :webhook_url)
        rescue StandardError
          nil
        end

        def default_exclude_tables
          %w[
            access_logs
            additional_services
            ahoy_events
            ahoy_visits
            alert_notifications
            bills
            consolidated_invoices
            email_logs
            field_test_events
            field_test_memberships
            invoices
            metrics
            notable_requests
            parking_state_transitions
            potential_margins
            picks
            push_notification_logs
            recharge_sessions
            ringover_events
            sms_logs
            spot_monthly_metrics
            spot_state_transitions
            spot_stats
            spot_type_metrics
            stripe_charges
            stripe_invoices
            stripe_refunds
            scalingo_scheduler_task_logs
            versions
          ]
        end
      end
    end
  end
end
