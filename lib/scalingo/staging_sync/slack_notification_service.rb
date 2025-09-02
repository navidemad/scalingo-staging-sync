# frozen_string_literal: true

module Scalingo
  module StagingSync
    class SlackNotificationService
      def initialize(logger: nil)
        @config = Scalingo::StagingSync.configuration
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

      # Service-specific methods for different components
      def anonymizer_step(message)
        notify_step(message, context: "")
      end

      def anonymizer_error(message)
        notify_warning(message, context: "⚠️")
      end

      def backup_step(message)
        notify_step(message, context: "")
      end

      def backup_error(message)
        notify_warning(message, context: "⚠️")
      end

      def restore_step(message)
        notify_step(message, context: "")
      end

      def restore_error(message)
        notify_warning(message, context: "⚠️")
      end

      def coordinator_step(message)
        notify_step(message, context: "")
      end

      def coordinator_error(message)
        notify_warning(message, context: "⚠️")
      end

      private

      def slack_enabled?
        return false unless @config.slack_enabled

        webhook_url = @config.slack_webhook_url
        !webhook_url.nil? && !webhook_url.empty?
      end

      def initialize_slack_client
        webhook_url = @config.slack_webhook_url
        Scalingo::StagingSync::SlackWebhookClient.new(webhook_url, logger: @logger) if webhook_url
      end

      def send_to_slack(message, options={})
        return unless @slack_client

        channel = @config.slack_channel
        options[:channel] = channel

        @slack_client.post_message(message, options)
      end

      def format_success_message(duration_minutes, source_app, target_app)
        [
          "✅ *Synchronisation Staging Réussie*",
          "",
          "• Durée: #{duration_minutes} minutes",
          "• Source: #{source_app}",
          "• Cible: #{target_app}",
          "• Anonymisation: ✅ Appliquée",
          "• Seeds: ✅ Exécutés",
          "",
          "URL de test: https://#{target_app}.osc-fr1.scalingo.io"
        ].join("\n")
      end

      def format_failure_message(error_message, target_app)
        [
          "❌ *Échec Synchronisation Staging*",
          "",
          "• Erreur: #{error_message}",
          "• App cible: #{target_app}",
          "",
          "Action requise: Vérifier les logs Scalingo",
          "```",
          "scalingo -a #{target_app} logs --lines 500",
          "```"
        ].join("\n")
      end

      def format_warning_message(warning_message)
        [
          "⚠️ *Avertissement Synchronisation Staging*",
          "",
          warning_message.to_s,
          "",
          "La synchronisation a continué malgré cet avertissement."
        ].join("\n")
      end

      def build_message(message, context)
        context ? "#{context} #{message}" : message
      end

      def build_error_message(error_message, context)
        context ? "#{context}: #{error_message}" : error_message
      end
    end
  end
end
