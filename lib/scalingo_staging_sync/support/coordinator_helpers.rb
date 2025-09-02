# frozen_string_literal: true

module ScalingoStagingSync
  module Support
    # Module containing helper methods for Coordinator
    module CoordinatorHelpers
      def cleanup_temp_files
        @logger.info "[Coordinator] Cleaning up temporary files..."

        temp_files =
          %w[production.tar.gz production.dump production.pgsql latest.pgsql filtered.toc].map do |f|
            @temp_dir.join(f)
          end

        cleaned_count = 0
        temp_files.each do |file|
          next unless File.exist?(file)

          FileUtils.rm_f(file)
          cleaned_count += 1
          @logger.debug "[Coordinator] Removed: #{file}"
        end

        @logger.info "[Coordinator] Cleaned up #{cleaned_count} temporary files"
      end

      def notify_start
        message = "🚀 Démarrage (Application cible: #{@target_app})"
        @logger.info "[Coordinator] Sending start notification: #{message}"
        @slack_notifier.coordinator_step(message)
      end

      def notify_step(message)
        @logger.info "[Coordinator] #{message}"
        @slack_notifier.coordinator_step(message)
      end

      def notify_success
        duration_minutes = ((Time.current - @start_time) / 60).round

        @logger.info "[Coordinator] Sync completed in #{duration_minutes} minutes"

        @slack_notifier.notify_success(duration_minutes, @source_app, @target_app)
      end

      def handle_error(error)
        @logger.error "[Coordinator] Staging sync failed: #{error.message}"
        @logger.error "[Coordinator] Backtrace:\n#{error.backtrace.first(10).join("\n")}"

        @slack_notifier.notify_failure(error.message, @target_app)

        @logger.info "[Coordinator] Performing emergency cleanup..."
        cleanup_temp_files
        raise error
      end
    end
  end
end
