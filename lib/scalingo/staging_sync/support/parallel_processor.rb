# frozen_string_literal: true

module Scalingo
  module StagingSync
    # Module for parallel processing of database operations
    module ParallelProcessor
      def create_anonymization_threads
        WORK_QUEUES.map do |connection_id, tables|
          Thread.new { process_tables_in_thread(connection_id, tables) }
        end
      end

      def process_tables_in_thread(connection_id, tables)
        log_thread_start(connection_id, tables)
        connection = establish_connection
        log_connection_established(connection_id)

        process_tables(connection, connection_id, tables)
      ensure
        close_connection(connection, connection_id)
      end

      def process_tables(connection, connection_id, tables)
        tables.each do |table|
          @logger.info "[DatabaseAnonymizerService][#{connection_id}] Processing table: #{table}"
          anonymize_table(connection, table)
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
        threads.each(&:join)
      end
    end
  end
end
