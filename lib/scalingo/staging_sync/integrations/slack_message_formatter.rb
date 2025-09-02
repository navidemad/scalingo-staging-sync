# frozen_string_literal: true

module Scalingo
  module StagingSync
    # Module for formatting Slack messages
    module SlackMessageFormatter
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
