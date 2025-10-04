# frozen_string_literal: true

require "test_helper"

module ScalingoStagingSync
  module Database
    class ColumnValidatorTest < Minitest::Test
      include TestHelpers
      include ColumnValidator

      def setup
        @connection = Minitest::Mock.new
        @logger = ActiveSupport::TaggedLogging.new(Logger.new(IO::NULL))
      end

      def test_validate_columns_exist_with_all_columns_present
        required_columns = %w[id email first_name]
        existing_columns = %w[id email first_name last_name created_at]

        stub_fetch_columns("users", existing_columns)

        result = validate_columns_exist(@connection, "users", required_columns)

        assert result[:success], "Validation should pass when all columns exist"
        assert_empty result[:missing_columns], "Should have no missing columns"
        assert_empty result[:errors], "Should have no errors"
      end

      def test_validate_columns_exist_with_missing_columns
        required_columns = %w[id email first_name zendesk_user_id]
        existing_columns = %w[id email last_name] # missing first_name and zendesk_user_id

        stub_fetch_columns("users", existing_columns)

        result = validate_columns_exist(@connection, "users", required_columns)

        refute result[:success], "Validation should fail when columns are missing"
        assert_equal %w[first_name zendesk_user_id], result[:missing_columns].sort
        assert_includes result[:errors].join, "first_name"
        assert_includes result[:errors].join, "zendesk_user_id"
      end

      def test_validate_columns_exist_with_nonexistent_table
        stub_fetch_columns("nonexistent_table", nil)

        result = validate_columns_exist(@connection, "nonexistent_table", %w[id])

        refute result[:success], "Validation should fail for nonexistent table"
        assert_includes result[:errors].join, "does not exist"
      end

      def test_anonymized_at_column_exists_returns_true_when_present
        stub_fetch_columns("users", %w[id email anonymized_at])

        result = anonymized_at_column_exists?(@connection, "users")

        assert result, "Should return true when anonymized_at exists"
      end

      def test_anonymized_at_column_exists_returns_false_when_absent
        stub_fetch_columns("users", %w[id email])

        result = anonymized_at_column_exists?(@connection, "users")

        refute result, "Should return false when anonymized_at doesn't exist"
      end

      private

      def stub_fetch_columns(table, columns)
        if columns.nil?
          result = QueryResult.new([])
        else
          rows = columns.map { |col| { "column_name" => col } }
          result = QueryResult.new(rows)
        end
        @connection.expect(:exec_params, result, [String, [table]])
      end

      class QueryResult
        def initialize(rows)
          @rows = rows
        end

        def ntuples
          @rows.size
        end

        def map(&)
          @rows.map(&)
        end
      end
    end
  end
end
