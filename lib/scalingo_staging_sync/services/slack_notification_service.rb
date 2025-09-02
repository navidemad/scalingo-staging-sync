# frozen_string_literal: true

require_relative "../integrations/slack_message_formatter"
require_relative "../integrations/slack_service_delegates"

module ScalingoStagingSync
  module Services
    class SlackNotificationService
      include Integrations::SlackMessageFormatter
      include Integrations::SlackServiceDelegates

      def initialize(logger: nil)
        @config = ScalingoStagingSync.configuration
        @logger = logger || @config.logger
        @enabled = slack_enabled?
        @slack_client = initialize_slack_client if @enabled
      end

      def notify_step(message, context: nil)
        return unless @enabled

        full_message = build_message(message, context)
        @logger.info "[SlackNotificationService] Sending step notification: #{full_message}"

        send_to_slack(full_message, username: "Demo Database Sync Progress", icon_emoji: ":gear:")
      rescue StandardError => e
        @logger.warn "[SlackNotificationService] Failed to send step notification: #{e.message}"
      end

      def notify_success(duration_minutes, source_app, target_app)
        return unless @enabled

        @logger.info "[SlackNotificationService] Sending success notification"

        message = format_success_message(duration_minutes, source_app, target_app)
        send_to_slack(message, username: "Demo Database Sync", icon_emoji: ":white_check_mark:")
      rescue StandardError => e
        @logger.warn "[SlackNotificationService] Failed to send success notification: #{e.message}"
      end

      def notify_failure(error_message, target_app, context: nil)
        return unless @enabled

        full_message = build_error_message(error_message, context)
        @logger.info "[SlackNotificationService] Sending failure notification: #{full_message}"

        message = format_failure_message(full_message, target_app)
        send_to_slack(message, username: "Demo Database Sync", icon_emoji: ":x:")
      rescue StandardError => e
        @logger.warn "[SlackNotificationService] Failed to send failure notification: #{e.message}"
      end

      def notify_warning(warning_message, context: nil)
        return unless @enabled

        full_message = build_message(warning_message, context)
        @logger.info "[SlackNotificationService] Sending warning notification: #{full_message}"

        message = format_warning_message(full_message)
        send_to_slack(message, username: "Demo Database Sync", icon_emoji: ":warning:")
      rescue StandardError => e
        @logger.warn "[SlackNotificationService] Failed to send warning notification: #{e.message}"
      end

      private

      def slack_enabled?
        return false unless @config.slack_enabled

        webhook_url = @config.slack_webhook_url
        !webhook_url.nil? && !webhook_url.empty?
      end

      def initialize_slack_client
        webhook_url = @config.slack_webhook_url
        ScalingoStagingSync::Integrations::SlackWebhookClient.new(webhook_url, logger: @logger) if webhook_url
      end

      def send_to_slack(message, options={})
        return unless @slack_client

        channel = @config.slack_channel
        options[:channel] = channel

        @slack_client.post_message(message, options)
      end
    end
  end
end
