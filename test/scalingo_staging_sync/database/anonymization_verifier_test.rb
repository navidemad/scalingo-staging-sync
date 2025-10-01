# frozen_string_literal: true

require "test_helper"

module ScalingoStagingSync
  module Database
    class AnonymizationVerifierTest < Minitest::Test
      include TestHelpers
      include AnonymizationVerifier

      def setup
        @connection = Minitest::Mock.new
        @logger = ActiveSupport::TaggedLogging.new(Logger.new(IO::NULL))
      end

      def test_verify_users_anonymization_passes_with_clean_data
        # Mock all verification queries to return 0 (no issues)
        setup_clean_verification_mocks

        result = verify_users_anonymization(@connection)

        assert result[:success], "Verification should pass with clean data"
        assert_empty result[:issues], "Should have no issues"
      end

      def test_verify_users_anonymization_fails_with_production_emails
        # Mock production email check to return 5 problematic emails
        @connection.expect(:exec, mock_result({ "count" => "5" }), [String])
        # Mock other checks to return 0
        6.times { @connection.expect(:exec, mock_result({ "count" => "0" }), [String]) }

        result = verify_users_anonymization(@connection)

        refute result[:success], "Verification should fail with production emails"
        assert_includes result[:issues].join, "production-like email addresses"
      end

      def test_verify_phone_numbers_anonymization_passes
        # Mock phone checks to return 0 (no issues)
        @connection.expect(:exec, mock_result({ "count" => "0" }), [String])
        @connection.expect(:exec, mock_result({ "count" => "0" }), [String])

        result = verify_phone_numbers_anonymization(@connection)

        assert result[:success], "Verification should pass"
        assert_empty result[:issues], "Should have no issues"
      end

      def test_verify_payment_methods_anonymization_passes
        # Mock card check to return 0 (no issues)
        @connection.expect(:exec, mock_result({ "count" => "0" }), [String])

        result = verify_payment_methods_anonymization(@connection)

        assert result[:success], "Verification should pass"
        assert_empty result[:issues], "Should have no issues"
      end

      def test_verify_payment_methods_anonymization_fails_with_real_cards
        # Mock card check to return 3 problematic cards
        @connection.expect(:exec, mock_result({ "count" => "3" }), [String])

        result = verify_payment_methods_anonymization(@connection)

        refute result[:success], "Verification should fail with real card numbers"
        assert_includes result[:issues].join, "non-anonymized card numbers"
      end

      private

      def setup_clean_verification_mocks
        # 7 queries for users verification (all checks)
        7.times { @connection.expect(:exec, mock_result({ "count" => "0" }), [String]) }
      end

      def mock_result(row_hash)
        result = Minitest::Mock.new
        result.expect(:[], row_hash["count"], [String])
        [result]
      end
    end
  end
end
