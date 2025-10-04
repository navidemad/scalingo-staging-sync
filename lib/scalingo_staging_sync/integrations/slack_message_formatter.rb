# frozen_string_literal: true

module ScalingoStagingSync
  module Integrations
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

      def format_database_size_message(size_info)
        message_parts = [
          "📊 *Estimation Taille Base de Données*",
          "",
          "• Taille totale estimée: *#{size_info[:total_size_pretty]}*",
          "• Tables incluses: #{size_info[:total_tables]}",
          "• Tables exclues: #{size_info[:excluded_tables_count]}"
        ]

        if size_info[:table_sizes].any?
          message_parts << ""
          message_parts << "📈 Top 10 tables les plus volumineuses:"
          size_info[:table_sizes].each_with_index do |table, index|
            message_parts << "  #{index + 1}. #{table[:table]}: #{table[:size_pretty]}"
          end
        end

        message_parts.join("\n")
      end
    end
  end
end
