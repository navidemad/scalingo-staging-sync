# frozen_string_literal: true

require "test_helper"

class DatabaseAnonymizerServiceTest < Minitest::Test
  def setup
    super
    stub_rails
    @logger = ActiveSupport::TaggedLogging.new(Logger.new(StringIO.new))
    @database_url = "postgresql://user:pass@localhost/test_db"

    ScalingoStagingSync.configure do |config|
      config.logger = @logger
      config.parallel_connections = 2
      config.anonymization_tables = []
      config.verify_anonymization = false
      config.run_pii_scan = false
      config.anonymization_audit_file = nil
    end

    @service = ScalingoStagingSync::Services::DatabaseAnonymizerService.new(
      @database_url,
      logger: @logger
    )
  end

  def teardown
    unstub_rails
    super
  end

  describe "initialization" do
    def setup
      super
      stub_rails
      @logger = ActiveSupport::TaggedLogging.new(Logger.new(StringIO.new))
      @database_url = "postgresql://user:pass@localhost/test_db"

      ScalingoStagingSync.configure do |config|
        config.logger = @logger
        config.parallel_connections = 2
        config.anonymization_tables = []
        config.verify_anonymization = false
        config.run_pii_scan = false
        config.anonymization_audit_file = nil
      end
    end

    def test_initializes_with_database_url
      service = ScalingoStagingSync::Services::DatabaseAnonymizerService.new(
        @database_url,
        logger: @logger
      )

      refute_nil service.instance_variable_get(:@database_url)
      assert_equal @logger, service.instance_variable_get(:@logger)
      refute_nil service.instance_variable_get(:@slack_notifier)
    end

    def test_uses_configured_anonymization_tables
      ScalingoStagingSync.configuration.anonymization_tables = [
        { table: "users", strategy: :user_anonymization },
        { table: "emails", strategy: :email_anonymization }
      ]

      service = ScalingoStagingSync::Services::DatabaseAnonymizerService.new(
        @database_url,
        logger: @logger
      )

      tables = service.instance_variable_get(:@anonymization_tables)
      assert_equal 2, tables.size
      assert_equal "users", tables[0][:table]
      assert_equal "emails", tables[1][:table]
    end

    def test_generates_work_queues_for_parallel_connections
      ScalingoStagingSync.configure do |config|
        config.parallel_connections = 2
        config.anonymization_tables = [
          { table: "users", strategy: :user_anonymization },
          { table: "emails", strategy: :email_anonymization },
          { table: "addresses", strategy: :address_anonymization }
        ]
      end

      service = ScalingoStagingSync::Services::DatabaseAnonymizerService.new(
        @database_url,
        parallel_connections: 2,
        logger: @logger
      )

      work_queues = service.instance_variable_get(:@work_queues)
      assert_equal 2, work_queues.size
      assert work_queues.key?(:connection_1)
      assert work_queues.key?(:connection_2)
    end
  end

  describe "load_anonymization_tables" do
    def setup
      super
      stub_rails
      @logger = ActiveSupport::TaggedLogging.new(Logger.new(StringIO.new))
      @database_url = "postgresql://user:pass@localhost/test_db"

      ScalingoStagingSync.configure do |config|
        config.logger = @logger
        config.parallel_connections = 2
        config.verify_anonymization = false
        config.run_pii_scan = false
        config.anonymization_audit_file = nil
      end
    end

    def test_falls_back_to_legacy_tables_with_warning
      ScalingoStagingSync.configuration.anonymization_tables = []

      service = ScalingoStagingSync::Services::DatabaseAnonymizerService.new(
        @database_url,
        logger: @logger
      )

      logs = @logger.instance_variable_get(:@logdev).dev.string
      assert_includes logs, "DEPRECATION WARNING"
      assert_includes logs, "Using hardcoded anonymization tables"

      tables = service.instance_variable_get(:@anonymization_tables)
      assert_equal 3, tables.size
      table_names = tables.map { |t| t[:table] }
      assert_includes table_names, "users"
      assert_includes table_names, "phone_numbers"
      assert_includes table_names, "payment_methods"
    end
  end

  describe "validate_anonymization_tables!" do
    def setup
      super
      stub_rails
      @logger = ActiveSupport::TaggedLogging.new(Logger.new(StringIO.new))
      @database_url = "postgresql://user:pass@localhost/test_db"
    end

    def test_raises_on_missing_table_key
      config_tables = [{ strategy: :user_anonymization }]
      ScalingoStagingSync.configuration.anonymization_tables = config_tables

      error = assert_raises(ArgumentError) do
        ScalingoStagingSync::Services::DatabaseAnonymizerService.new(
          @database_url,
          logger: @logger
        )
      end

      assert_includes error.message, "missing required :table key"
    end

    def test_raises_on_both_strategy_and_query
      config_tables = [
        { table: "users", strategy: :user_anonymization, query: "UPDATE users SET name = 'test'" }
      ]
      ScalingoStagingSync.configuration.anonymization_tables = config_tables

      error = assert_raises(ArgumentError) do
        ScalingoStagingSync::Services::DatabaseAnonymizerService.new(
          @database_url,
          logger: @logger
        )
      end

      assert_includes error.message, "cannot have both :strategy and :query"
    end
  end

  describe "build_anonymization_query" do
    def setup
      super
      stub_rails
      @logger = ActiveSupport::TaggedLogging.new(Logger.new(StringIO.new))
      @database_url = "postgresql://user:pass@localhost/test_db"

      ScalingoStagingSync.configure do |config|
        config.logger = @logger
        config.parallel_connections = 2
        config.anonymization_tables = []
        config.verify_anonymization = false
        config.run_pii_scan = false
        config.anonymization_audit_file = nil
      end

      @service = ScalingoStagingSync::Services::DatabaseAnonymizerService.new(
        @database_url,
        logger: @logger
      )
    end

    def test_uses_custom_query_when_provided
      table_config = { table: "custom", query: "UPDATE custom SET field = NULL" }

      query = @service.send(:build_anonymization_query, table_config)

      assert_equal "UPDATE custom SET field = NULL", query
    end

    def test_uses_strategy_when_provided
      table_config = { table: "users", strategy: :user_anonymization }

      stub_strategy = lambda { |table, _condition|
        "UPDATE #{table} SET email = 'test@example.com'"
      }
      ScalingoStagingSync::Database::AnonymizationStrategies.stub(:get_strategy, ->(_strategy_name) { stub_strategy }) do
        query = @service.send(:build_anonymization_query, table_config)

        assert_includes query, "UPDATE users"
      end
    end

    def test_returns_nil_for_unknown_strategy
      table_config = { table: "unknown", strategy: :nonexistent_strategy }

      ScalingoStagingSync::Database::AnonymizationStrategies.stub(:get_strategy, nil) do
        query = @service.send(:build_anonymization_query, table_config)

        assert_nil query
      end
    end

    def test_adds_condition_to_query
      table_config = { table: "users", query: "UPDATE users SET email = NULL", condition: "id > 100" }

      query = @service.send(:build_anonymization_query, table_config)

      assert_includes query, "WHERE id > 100"
    end
  end

  describe "generate_work_queues" do
    def setup
      super
      stub_rails
      @logger = ActiveSupport::TaggedLogging.new(Logger.new(StringIO.new))
      @database_url = "postgresql://user:pass@localhost/test_db"
    end

    def test_distributes_tables_across_connections
      ScalingoStagingSync.configure do |config|
        config.parallel_connections = 3
        config.anonymization_tables = [
          { table: "table1", strategy: :user_anonymization },
          { table: "table2", strategy: :email_anonymization },
          { table: "table3", strategy: :address_anonymization },
          { table: "table4", strategy: :user_anonymization },
          { table: "table5", strategy: :email_anonymization }
        ]
      end

      service = ScalingoStagingSync::Services::DatabaseAnonymizerService.new(
        @database_url,
        logger: @logger
      )

      work_queues = service.instance_variable_get(:@work_queues)
      assert_equal 3, work_queues.size

      total_tables = work_queues.values.flatten.size
      assert_equal 5, total_tables
    end
  end

  describe "find_table_config" do
    def setup
      super
      stub_rails
      @logger = ActiveSupport::TaggedLogging.new(Logger.new(StringIO.new))
      @database_url = "postgresql://user:pass@localhost/test_db"

      ScalingoStagingSync.configure do |config|
        config.logger = @logger
        config.parallel_connections = 2
        config.verify_anonymization = false
        config.run_pii_scan = false
        config.anonymization_audit_file = nil
      end
    end

    def test_finds_config_by_table_name
      ScalingoStagingSync.configuration.anonymization_tables = [
        { table: "users", strategy: :user_anonymization },
        { table: "emails", strategy: :email_anonymization }
      ]

      service = ScalingoStagingSync::Services::DatabaseAnonymizerService.new(
        @database_url,
        logger: @logger
      )

      config = service.send(:find_table_config, "users")

      refute_nil config
      assert_equal "users", config[:table]
    end

    def test_returns_nil_for_unknown_table
      service = ScalingoStagingSync::Services::DatabaseAnonymizerService.new(
        @database_url,
        logger: @logger
      )

      config = service.send(:find_table_config, "nonexistent")

      assert_nil config
    end
  end

  describe "logging" do
    def setup
      super
      stub_rails
      @logger = ActiveSupport::TaggedLogging.new(Logger.new(StringIO.new))
      @database_url = "postgresql://user:pass@localhost/test_db"

      ScalingoStagingSync.configure do |config|
        config.logger = @logger
        config.parallel_connections = 2
        config.anonymization_tables = []
        config.verify_anonymization = false
        config.run_pii_scan = false
        config.anonymization_audit_file = nil
      end

      @service = ScalingoStagingSync::Services::DatabaseAnonymizerService.new(
        @database_url,
        logger: @logger
      )
    end

    def test_logs_start_anonymization
      @service.send(:log_start_anonymization)

      logs = @logger.instance_variable_get(:@logdev).dev.string
      assert_includes logs, "Starting parallel anonymization"
    end

    def test_logs_work_queues
      @service.send(:log_work_queues)

      logs = @logger.instance_variable_get(:@logdev).dev.string
      assert_includes logs, "Work queues configured"
    end
  end

  describe "error recovery" do
    def setup
      super
      stub_rails
      @logger = ActiveSupport::TaggedLogging.new(Logger.new(StringIO.new))
      @database_url = "postgresql://user:pass@localhost/test_db"

      ScalingoStagingSync.configure do |config|
        config.logger = @logger
        config.parallel_connections = 2
        config.anonymization_tables = []
        config.verify_anonymization = false
        config.run_pii_scan = false
        config.anonymization_audit_file = nil
      end

      @service = ScalingoStagingSync::Services::DatabaseAnonymizerService.new(
        @database_url,
        logger: @logger
      )
    end

    def test_continues_processing_other_tables_on_failure
      connection = Minitest::Mock.new

      def connection.exec(query)
        raise PG::Error, "Table error" if query.include?("users")

        Minitest::Mock.new.tap { |m| m.expect(:cmd_tuples, 10) }
      end

      @service.stub(:establish_connection, connection) do
        error = assert_raises(PG::Error) do
          @service.send(:anonymize_table, connection, "users")
        end

        assert_equal "Table error", error.message
      end
    end
  end
end
