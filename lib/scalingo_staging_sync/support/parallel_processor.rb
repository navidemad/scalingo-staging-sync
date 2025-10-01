# frozen_string_literal: true

module ScalingoStagingSync
  module Support
    # Module for parallel processing of database operations with error coordination
    module ParallelProcessor
      # Thread-safe error tracking across parallel operations
      class ThreadErrorTracker
        def initialize
          @errors = []
          @mutex = Mutex.new
          @stop_signal = false
        end

        def add_error(error, context={})
          @mutex.synchronize do
            @errors << { error: error, context: context, thread_id: Thread.current.object_id }
          end
        end

        def errors
          @mutex.synchronize { @errors.dup }
        end

        def any_errors?
          @mutex.synchronize { @errors.any? }
        end

        def signal_stop
          @mutex.synchronize { @stop_signal = true }
        end

        def should_stop?
          @mutex.synchronize { @stop_signal }
        end
      end

      def create_anonymization_threads
        @error_tracker = ThreadErrorTracker.new

        threads = @work_queues.map do |connection_id, tables|
          Thread.new { process_tables_in_thread(connection_id, tables) }
        end

        # Store threads for abort handling
        @anonymization_threads = threads
        threads
      end

      def process_tables_in_thread(connection_id, tables)
        log_thread_start(connection_id, tables)

        # Check for stop signal before establishing connection
        return if @error_tracker.should_stop?

        connection = establish_connection
        log_connection_established(connection_id)

        # Begin a top-level transaction if global rollback is enabled
        begin_global_transaction(connection, connection_id) if ScalingoStagingSync.configuration.anonymization_rollback_on_error

        process_tables(connection, connection_id, tables)

        # Commit global transaction if enabled and no errors occurred
        if ScalingoStagingSync.configuration.anonymization_rollback_on_error && !@error_tracker.any_errors?
          commit_global_transaction(connection, connection_id)
        end
      rescue StandardError => e
        handle_thread_error(e, connection_id, connection)
        raise
      ensure
        close_connection(connection, connection_id)
      end

      def process_tables(connection, connection_id, tables)
        tables.each do |table|
          # Check for stop signal before processing each table
          if @error_tracker.should_stop?
            @logger.warn(
              "[DatabaseAnonymizerService][#{connection_id}] Stopping due to error in another thread"
            )
            break
          end

          @logger.info "[DatabaseAnonymizerService][#{connection_id}] Processing table: #{table}"
          anonymize_table(connection, table)
        rescue StandardError => e
          # Record error and signal other threads to stop
          @error_tracker.add_error(e, { connection_id: connection_id, table: table })
          @error_tracker.signal_stop
          raise
        end
      end

      def log_thread_start(connection_id, tables)
        @logger.info(
          "[DatabaseAnonymizerService][#{connection_id}] Starting thread for tables: #{tables.join(', ')}"
        )
      end

      def log_connection_established(connection_id)
        @logger.info "[DatabaseAnonymizerService][#{connection_id}] Database connection established"
      end

      def close_connection(connection, connection_id)
        return unless connection

        connection.close
        @logger.info "[DatabaseAnonymizerService][#{connection_id}] Connection closed"
      end

      def wait_for_threads(threads)
        @logger.info "[DatabaseAnonymizerService] Waiting for all threads to complete..."

        # Wait for all threads and collect exceptions
        thread_exceptions = []
        threads.each do |thread|
          thread.join
        rescue StandardError => e
          thread_exceptions << e
        end

        # After all threads complete, check if there were any errors
        if @error_tracker.any_errors?
          handle_aggregated_errors(@error_tracker.errors)
        elsif thread_exceptions.any?
          # Re-raise first exception if no tracked errors but thread failed
          raise thread_exceptions.first
        end
      end

      private

      def begin_global_transaction(connection, connection_id)
        @logger.info "[DatabaseAnonymizerService][#{connection_id}] BEGIN global transaction"
        connection.exec("BEGIN")
      rescue PG::Error => e
        @logger.error(
          "[DatabaseAnonymizerService][#{connection_id}] Failed to begin global transaction: #{e.message}"
        )
        raise
      end

      def commit_global_transaction(connection, connection_id)
        @logger.info "[DatabaseAnonymizerService][#{connection_id}] COMMIT global transaction"
        connection.exec("COMMIT")
      rescue PG::Error => e
        @logger.error(
          "[DatabaseAnonymizerService][#{connection_id}] Failed to commit global transaction: #{e.message}"
        )
        rollback_global_transaction(connection, connection_id)
        raise
      end

      def rollback_global_transaction(connection, connection_id)
        @logger.warn "[DatabaseAnonymizerService][#{connection_id}] ROLLBACK global transaction"
        connection.exec("ROLLBACK")
      rescue PG::Error => e
        @logger.error(
          "[DatabaseAnonymizerService][#{connection_id}] Failed to rollback global transaction: #{e.message}"
        )
      end

      def handle_thread_error(error, connection_id, connection)
        @logger.error(
          "[DatabaseAnonymizerService][#{connection_id}] Thread error: #{error.class} - #{error.message}"
        )

        # Rollback global transaction if enabled
        return unless ScalingoStagingSync.configuration.anonymization_rollback_on_error && connection

        rollback_global_transaction(connection, connection_id)
      end

      def handle_aggregated_errors(errors)
        @logger.error "[DatabaseAnonymizerService] Anonymization failed with #{errors.size} error(s):"

        errors.each_with_index do |error_info, index|
          error = error_info[:error]
          context = error_info[:context]
          @logger.error(
            "[DatabaseAnonymizerService] Error #{index + 1}: #{error.class} - #{error.message} " \
            "(thread: #{error_info[:thread_id]}, connection: #{context[:connection_id]}, table: #{context[:table]})"
          )
        end

        # Raise composite error with all error messages
        error_messages = errors.map do |e|
          "#{e[:context][:table]}: #{e[:error].message}"
        end.join("; ")

        raise PG::Error, "Multiple anonymization failures: #{error_messages}"
      end
    end
  end
end
