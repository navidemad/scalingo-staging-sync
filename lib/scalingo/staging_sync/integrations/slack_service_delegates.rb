# frozen_string_literal: true

module Scalingo
  module StagingSync
    # Module for service-specific Slack notification methods
    module SlackServiceDelegates
      # Anonymizer service notifications
      def anonymizer_step(message)
        notify_step(message, context: "")
      end

      def anonymizer_error(message)
        notify_warning(message, context: "⚠️")
      end

      # Backup service notifications
      def backup_step(message)
        notify_step(message, context: "")
      end

      def backup_error(message)
        notify_warning(message, context: "⚠️")
      end

      # Restore service notifications
      def restore_step(message)
        notify_step(message, context: "")
      end

      def restore_error(message)
        notify_warning(message, context: "⚠️")
      end

      # Coordinator notifications
      def coordinator_step(message)
        notify_step(message, context: "")
      end

      def coordinator_error(message)
        notify_warning(message, context: "⚠️")
      end
    end
  end
end
