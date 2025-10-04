# frozen_string_literal: true

require_relative "../database/size_estimator"

module ScalingoStagingSync
  module Support
    # Module containing helper methods for Coordinator
    module CoordinatorHelpers
      include Database::SizeEstimator

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

      def estimate_current_database_size
        @logger.info "[Coordinator] Estimating current database size..."
        connection = nil
        connection = PG.connect(@database_url)
        size_info = estimate_database_size(connection)

        log_size_info(size_info)
        @slack_notifier.notify_database_size(size_info)
      rescue PG::Error => e
        @logger.warn "[Coordinator] Could not estimate database size: #{e.message}"
      ensure
        connection&.close
      end

      def log_size_info(size_info)
        @logger.info "[Coordinator] Current database size: #{size_info[:total_size_pretty]} " \
                     "(#{size_info[:total_tables]} tables, #{size_info[:excluded_tables_count]} will be excluded)"

        return unless size_info[:table_sizes].any?

        @logger.info "[Coordinator] Largest tables:"
        size_info[:table_sizes].first(5).each_with_index do |table, index|
          @logger.info "[Coordinator]   #{index + 1}. #{table[:table]}: #{table[:size_pretty]}"
        end
      end
    end
  end
end
