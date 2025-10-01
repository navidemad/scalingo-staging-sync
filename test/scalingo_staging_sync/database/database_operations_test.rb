# frozen_string_literal: true

require "test_helper"

class DatabaseOperationsTest < Minitest::Test
  class TestService
    include ScalingoStagingSync::Database::DatabaseOperations

    attr_reader :logger, :database_url

    def initialize(database_url, logger)
      @database_url = database_url
      @logger = logger
      @slack_notifier = SlackNotifierMock.new
    end
  end

  class SlackNotifierMock
    def restore_step(_message); end

    def restore_error(_message); end
  end

  def setup
    super
    stub_rails
    @logger = ActiveSupport::TaggedLogging.new(Logger.new(StringIO.new))
    @database_url = "postgresql://user:pass@localhost:5432/test_db"
    @service = TestService.new(@database_url, @logger)
    puts "DEBUG: @service after creation = #{@service.inspect[0..100]}" if ENV["DEBUG"]
  end

  def teardown
    unstub_rails
    super
  end

  describe "recreate_database" do
    def setup
      super
      stub_rails
      @logger = ActiveSupport::TaggedLogging.new(Logger.new(StringIO.new))
      @database_url = "postgresql://user:pass@localhost:5432/test_db"
      @service = TestService.new(@database_url, @logger)
    end

    def test_calls_drop_and_create_in_sequence
      @service.stub(:drop_database, nil) do
        @service.stub(:create_database, nil) do
          @service.recreate_database

          logs = @logger.instance_variable_get(:@logdev).dev.string
          assert_includes logs, "Recreating database for clean restore"
          assert_includes logs, "Database recreated successfully"
        end
      end
    end
  end

  describe "drop_database" do
    def setup
      super
      stub_rails
      @logger = ActiveSupport::TaggedLogging.new(Logger.new(StringIO.new))
      @database_url = "postgresql://user:pass@localhost:5432/test_db"
      @service = TestService.new(@database_url, @logger)
    end

    def test_runs_rails_db_drop
      drop_called = false
      @service.stub(
        :system,
        lambda { |env, *args|
          if args.include?("db:drop")
            assert_equal @database_url, env["DATABASE_URL"]
            assert_equal "1", env["DISABLE_DATABASE_ENVIRONMENT_CHECK"]
            drop_called = true
            true
          end
        }
      ) do
        @service.drop_database
        assert drop_called, "Expected db:drop to be called"
      end

      logs = @logger.instance_variable_get(:@logdev).dev.string
      assert_includes logs, "Dropping existing database using Rails db:drop"
      assert_includes logs, "Database dropped successfully"
    end

    def test_continues_on_drop_failure
      @service.stub(:system, false) do
        @service.drop_database

        logs = @logger.instance_variable_get(:@logdev).dev.string
        assert_includes logs, "db:drop failed (database might not exist), continuing"
      end
    end
  end

  describe "create_database" do
    def setup
      super
      stub_rails
      @logger = ActiveSupport::TaggedLogging.new(Logger.new(StringIO.new))
      @database_url = "postgresql://user:pass@localhost:5432/test_db"
      @service = TestService.new(@database_url, @logger)
    end

    def test_runs_rails_db_create
      create_called = false
      @service.stub(
        :system,
        lambda { |env, *args|
          if args.include?("db:create")
            assert_equal @database_url, env["DATABASE_URL"]
            create_called = true
          end
          true
        }
      ) do
        @service.create_database
        assert create_called, "Expected db:create to be called"
      end

      logs = @logger.instance_variable_get(:@logdev).dev.string
      assert_includes logs, "Creating fresh database using Rails db:create"
      assert_includes logs, "Database created successfully"
    end

    def test_raises_error_on_create_failure
      @service.stub(:system, false) do
        error = assert_raises(RuntimeError) do
          @service.create_database
        end

        assert_equal "Failed to create database", error.message

        logs = @logger.instance_variable_get(:@logdev).dev.string
        assert_includes logs, "Failed to create database with db:create"
      end
    end
  end

  describe "run_migrations" do
    def setup
      super
      stub_rails
      @logger = ActiveSupport::TaggedLogging.new(Logger.new(StringIO.new))
      @database_url = "postgresql://user:pass@localhost:5432/test_db"
      @service = TestService.new(@database_url, @logger)
    end

    def test_runs_rails_db_migrate
      migrate_called = false
      @service.stub(
        :system,
        lambda { |env, *args|
          if args.include?("db:migrate")
            assert_equal @database_url, env["DATABASE_URL"]
            migrate_called = true
            true
          end
        }
      ) do
        @service.run_migrations
        assert migrate_called, "Expected db:migrate to be called"
      end

      logs = @logger.instance_variable_get(:@logdev).dev.string
      assert_includes logs, "Running database migrations"
      assert_includes logs, "Migrations completed successfully"
    end

    def test_raises_error_on_migration_failure
      @service.stub(:system, false) do
        error = assert_raises(RuntimeError) do
          @service.run_migrations
        end

        assert_equal "Database migrations failed", error.message

        logs = @logger.instance_variable_get(:@logdev).dev.string
        assert_includes logs, "Migration failed"
      end
    end
  end

  describe "display_installed_extensions" do
    def setup
      super
      stub_rails
      @logger = ActiveSupport::TaggedLogging.new(Logger.new(StringIO.new))
      @database_url = "postgresql://user:pass@localhost:5432/test_db"
      @service = TestService.new(@database_url, @logger)
    end

    def test_displays_extensions_successfully
      output = "uuid-ossp  | 1.1\npostgis    | 3.1"
      status = Minitest::Mock.new
      status.expect(:success?, true)

      Open3.stub(:capture3, [output, "", status]) do
        @service.display_installed_extensions

        logs = @logger.instance_variable_get(:@logdev).dev.string
        assert_includes logs, "Checking installed PostgreSQL extensions"
        assert_includes logs, "Installed extensions:"
        assert_includes logs, "uuid-ossp"
        assert_includes logs, "postgis"

        status.verify
      end
    end

    def test_handles_no_extensions
      output = ""
      status = Minitest::Mock.new
      status.expect(:success?, true)

      Open3.stub(:capture3, [output, "", status]) do
        @service.display_installed_extensions

        logs = @logger.instance_variable_get(:@logdev).dev.string
        assert_includes logs, "No additional extensions installed"

        status.verify
      end
    end

    def test_handles_query_failure
      status = Minitest::Mock.new
      status.expect(:success?, false)

      Open3.stub(:capture3, ["", "", status]) do
        @service.display_installed_extensions

        logs = @logger.instance_variable_get(:@logdev).dev.string
        assert_includes logs, "Failed to query installed extensions"

        status.verify
      end
    end
  end
end
