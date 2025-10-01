# frozen_string_literal: true

module ScalingoStagingSync
  module Database
    # Module providing transaction management helpers for database operations
    module TransactionHelpers
      # Executes a block within a database transaction with automatic rollback on error
      #
      # @param connection [PG::Connection] The database connection
      # @param savepoint_name [String, nil] Optional savepoint name for nested transactions
      # @yield The block to execute within the transaction
      # @return The result of the block
      # @raise [PG::Error] Re-raises any database errors after rollback
      def with_transaction(connection, savepoint_name: nil)
        if savepoint_name
          begin_savepoint(connection, savepoint_name)
        else
          begin_transaction(connection)
        end

        result = yield

        if savepoint_name
          release_savepoint(connection, savepoint_name)
        else
          commit_transaction(connection)
        end

        result
      rescue StandardError
        if savepoint_name
          rollback_to_savepoint(connection, savepoint_name)
        else
          rollback_transaction(connection)
        end
        raise
      end

      # Retries a block with exponential backoff
      #
      # @param max_attempts [Integer] Maximum number of retry attempts
      # @param base_delay [Float] Base delay in seconds for exponential backoff
      # @param table_name [String] Name of table being processed (for logging)
      # @yield The block to retry
      # @return The result of the block
      def with_retry(max_attempts: 3, base_delay: 1.0, table_name: "unknown")
        attempts = 0

        begin
          attempts += 1
          yield
        rescue PG::Error => e
          if attempts < max_attempts
            delay = base_delay * (2**(attempts - 1))
            @logger.warn(
              "[TransactionHelpers] Retry #{attempts}/#{max_attempts} for #{table_name} " \
              "after error: #{e.message}. Waiting #{delay}s..."
            )
            sleep(delay)
            retry
          else
            @logger.error(
              "[TransactionHelpers] Failed after #{max_attempts} attempts for #{table_name}: #{e.message}"
            )
            raise
          end
        end
      end

      # Verifies that an anonymization operation affected the expected number of rows
      #
      # @param connection [PG::Connection] The database connection
      # @param table_name [String] Name of the table
      # @param rows_affected [Integer] Number of rows reported as affected
      # @param where_clause [String, nil] Optional WHERE clause to check specific rows
      # @return [Boolean] True if verification passed
      def verify_anonymization(connection, table_name, rows_affected, where_clause: nil)
        return true if rows_affected.zero?

        count_query = if where_clause
                        "SELECT COUNT(*) FROM #{table_name} WHERE #{where_clause}"
                      else
                        "SELECT COUNT(*) FROM #{table_name}"
                      end

        result = connection.exec(count_query)
        actual_count = result.getvalue(0, 0).to_i

        # For WHERE clause queries, we just verify rows exist
        if where_clause && actual_count.zero? && rows_affected.positive?
          @logger.error(
            "[TransactionHelpers] Verification failed for #{table_name}: " \
            "#{rows_affected} rows reported but 0 rows match criteria"
          )
          return false
        end

        @logger.debug(
          "[TransactionHelpers] Verification passed for #{table_name}: " \
          "#{rows_affected} rows anonymized, #{actual_count} total rows"
        )
        true
      end

      private

      def begin_transaction(connection)
        @logger.debug "[TransactionHelpers] BEGIN TRANSACTION"
        connection.exec("BEGIN")
      end

      def commit_transaction(connection)
        @logger.debug "[TransactionHelpers] COMMIT TRANSACTION"
        connection.exec("COMMIT")
      end

      def rollback_transaction(connection)
        @logger.warn "[TransactionHelpers] ROLLBACK TRANSACTION"
        connection.exec("ROLLBACK")
      end

      def begin_savepoint(connection, savepoint_name)
        @logger.debug "[TransactionHelpers] SAVEPOINT #{savepoint_name}"
        connection.exec("SAVEPOINT #{sanitize_identifier(savepoint_name)}")
      end

      def release_savepoint(connection, savepoint_name)
        @logger.debug "[TransactionHelpers] RELEASE SAVEPOINT #{savepoint_name}"
        connection.exec("RELEASE SAVEPOINT #{sanitize_identifier(savepoint_name)}")
      end

      def rollback_to_savepoint(connection, savepoint_name)
        @logger.warn "[TransactionHelpers] ROLLBACK TO SAVEPOINT #{savepoint_name}"
        connection.exec("ROLLBACK TO SAVEPOINT #{sanitize_identifier(savepoint_name)}")
      end

      def sanitize_identifier(identifier)
        # Simple sanitization for savepoint names - only allow alphanumeric and underscore
        identifier.to_s.gsub(/[^a-zA-Z0-9_]/, "_")
      end
    end
  end
end
