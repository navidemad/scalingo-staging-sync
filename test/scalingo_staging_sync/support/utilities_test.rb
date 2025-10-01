# frozen_string_literal: true

require "test_helper"

class UtilitiesTest < Minitest::Test
  class UtilitiesTestClass
    include ScalingoStagingSync::Support::Utilities

    attr_reader :logger

    def initialize(logger)
      @logger = logger
    end
  end

  def setup
    super
    @logger = ActiveSupport::TaggedLogging.new(Logger.new(StringIO.new))
    @util = UtilitiesTestClass.new(@logger)
  end

  describe "format_bytes" do
    def setup
      super
      @logger = ActiveSupport::TaggedLogging.new(Logger.new(StringIO.new))
      @util = UtilitiesTestClass.new(@logger)
    end

    def test_formats_bytes_correctly
      assert_equal "0B", @util.format_bytes(0)
      assert_equal "1.0KB", @util.format_bytes(1024)
      assert_equal "1.0MB", @util.format_bytes(1024 * 1024)
      assert_equal "1.0GB", @util.format_bytes(1024 * 1024 * 1024)
      assert_equal "500.0B", @util.format_bytes(500)
      assert_equal "1.5KB", @util.format_bytes(1536)
      assert_equal "2.5MB", @util.format_bytes(2.5 * 1024 * 1024)
    end

    def test_handles_zero_and_nil_values
      assert_equal "0B", @util.format_bytes(0)
      assert_equal "0B", @util.format_bytes(nil)
    end

    def test_handles_very_large_values
      assert_equal "1.0TB", @util.format_bytes(1024 * 1024 * 1024 * 1024)
    end
  end

  describe "with_retry" do
    def setup
      super
      @logger = ActiveSupport::TaggedLogging.new(Logger.new(StringIO.new))
      @util = UtilitiesTestClass.new(@logger)
    end

    def test_succeeds_on_first_attempt
      attempts = 0

      result = @util.with_retry do
        attempts += 1
        "success"
      end

      assert_equal "success", result
      assert_equal 1, attempts
    end

    def test_retries_on_retryable_error
      attempts = 0

      result = @util.with_retry(max_retries: 2) do
        attempts += 1
        raise Errno::ECONNRESET if attempts < 2

        "success"
      end

      assert_equal "success", result
      assert_equal 2, attempts

      logs = @logger.instance_variable_get(:@logdev).dev.string
      assert_includes logs, "Retrying after error"
    end

    def test_does_not_retry_non_retryable_errors
      attempts = 0

      error = assert_raises(ArgumentError) do
        @util.with_retry(max_retries: 3) do
          attempts += 1
          raise ArgumentError, "Non-retryable error"
        end
      end

      assert_equal "Non-retryable error", error.message
      assert_equal 1, attempts
    end

    def test_gives_up_after_max_retries
      attempts = 0

      assert_raises(Errno::ECONNRESET) do
        @util.with_retry(max_retries: 2) do
          attempts += 1
          raise Errno::ECONNRESET
        end
      end

      assert_equal 2, attempts
    end
  end

  describe "log_context" do
    def setup
      super
      @logger = ActiveSupport::TaggedLogging.new(Logger.new(StringIO.new))
      @util = UtilitiesTestClass.new(@logger)
    end

    def test_logs_with_context
      @util.log_context(:info, "Test message", key1: "value1", key2: "value2")

      logs = @logger.instance_variable_get(:@logdev).dev.string
      assert_includes logs, "Test message"
      assert_includes logs, "key1"
      assert_includes logs, "value1"
      assert_includes logs, "key2"
      assert_includes logs, "value2"
    end

    def test_supports_different_log_levels
      %i[debug info warn error fatal].each do |level|
        logger = ActiveSupport::TaggedLogging.new(Logger.new(StringIO.new))
        util = UtilitiesTestClass.new(logger)

        util.log_context(level, "Test message")

        logs = logger.instance_variable_get(:@logdev).dev.string
        assert_includes logs, "Test message"
      end
    end

    def test_handles_empty_context
      @util.log_context(:info, "Message with no context")

      logs = @logger.instance_variable_get(:@logdev).dev.string
      assert_includes logs, "Message with no context"
    end

    def test_formats_context_nicely
      @util.log_context(:info, "Operation", file: "/tmp/backup.tar", size: 1024, status: :success)

      logs = @logger.instance_variable_get(:@logdev).dev.string
      assert_includes logs, "Operation"
      assert_includes logs, "file"
      assert_includes logs, "/tmp/backup.tar"
      assert_includes logs, "size"
      assert_includes logs, "1024"
      assert_includes logs, "status"
      assert_includes logs, "success"
    end
  end
end
