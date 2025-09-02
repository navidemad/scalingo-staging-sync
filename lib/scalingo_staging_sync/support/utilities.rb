# frozen_string_literal: true

module ScalingoStagingSync
  module Support
    # Utility module for common helper methods
    module Utilities
      def log_context(level, message, context={})
        formatted_context = context.map { |k, v| "#{k}=#{v}" }.join(" ")
        full_message = "[#{self.class.name.split('::').last}] #{message}"
        full_message += " - #{formatted_context}" unless context.empty?

        @logger.send(level, full_message)
      end

      def format_bytes(bytes)
        return "0B" if bytes.nil? || bytes == 0

        units = %w[B KB MB GB TB]
        index = (Math.log(bytes) / Math.log(1024)).floor
        size = (bytes.to_f / (1024**index)).round(2)

        "#{size}#{units[index]}"
      end

      def with_retry(max_retries: 3, retry_delay: 5)
        attempts = 0
        begin
          attempts += 1
          yield
        rescue StandardError => e
          raise unless attempts < max_retries && retryable_error?(e)

          log_context(:warn, "Retrying after error", attempt: attempts, max_attempts: max_retries, error: e.message)
          sleep(retry_delay * attempts) # Exponential backoff
          retry
        end
      end

      def retryable_error?(error)
        # Retry on network errors and timeouts
        case error
        when Net::ReadTimeout, Net::OpenTimeout, Errno::ECONNRESET, Errno::ETIMEDOUT
          true
        when StandardError
          error.message.include?("timeout") || error.message.include?("connection")
        else
          false
        end
      end
    end
  end
end
