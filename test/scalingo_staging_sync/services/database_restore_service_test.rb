# frozen_string_literal: true

require "test_helper"

class DatabaseRestoreServiceTest < Minitest::Test
  def setup
    super
    stub_rails
    @logger = ActiveSupport::TaggedLogging.new(Logger.new(StringIO.new))
    @database_url = "postgresql://user:pass@localhost/test_db"

    ScalingoStagingSync.configure do |config|
      config.logger = @logger
      config.postgis = false
    end

    @service = ScalingoStagingSync::Services::DatabaseRestoreService.new(
      @database_url,
      logger: @logger
    )
  end

  def teardown
    unstub_rails
    super
  end

  describe "initialization" do
    def test_initializes_with_database_url
      service = ScalingoStagingSync::Services::DatabaseRestoreService.new(
        @database_url,
        logger: @logger
      )

      assert_equal @database_url, service.instance_variable_get(:@database_url)
      assert_equal @logger, service.instance_variable_get(:@logger)
      refute_nil service.instance_variable_get(:@slack_notifier)
    end

    def test_handles_postgis_url_conversion
      ScalingoStagingSync.configure do |config|
        config.postgis = true
      end

      url = "postgresql://user:pass@localhost/test_db"
      service = ScalingoStagingSync::Services::DatabaseRestoreService.new(
        url,
        logger: @logger
      )

      assert_equal "postgisql://user:pass@localhost/test_db",
                   service.instance_variable_get(:@database_url)
      assert_equal "postgresql://user:pass@localhost/test_db",
                   service.instance_variable_get(:@pg_url)
    ensure
      ScalingoStagingSync.configure do |config|
        config.postgis = false
      end
    end
  end

  describe "restore!" do
    def setup
      super
      stub_rails
      @logger = ActiveSupport::TaggedLogging.new(Logger.new(StringIO.new))
      @database_url = "postgresql://user:pass@localhost/test_db"
      ScalingoStagingSync.configure do |config|
        config.logger = @logger
        config.postgis = false
      end
      @service = ScalingoStagingSync::Services::DatabaseRestoreService.new(@database_url, logger: @logger)
    end

    def test_successful_restore_with_pg_restore
      backup_file = File.join(@test_dir, "backup.tar")
      FileUtils.touch(backup_file)

      @service.stub(:pg_restore_available?, true) do
        @service.stub(:recreate_database, nil) do
          @service.stub(:execute_pg_restore, nil) do
            @service.stub(:run_migrations, nil) do
              @service.stub(:display_installed_extensions, nil) do
                @service.restore!(backup_file)

                logs = @logger.instance_variable_get(:@logdev).dev.string
                assert_includes logs, "Starting database restore process"
                assert_includes logs, "Using pg_restore for database restoration"
                assert_includes logs, "Database restore completed successfully"
              end
            end
          end
        end
      end
    end

    def test_successful_restore_with_psql_fallback
      backup_file = File.join(@test_dir, "backup.sql")
      FileUtils.touch(backup_file)

      @service.stub(:pg_restore_available?, false) do
        @service.stub(:execute_psql_restore, nil) do
          @service.stub(:run_migrations, nil) do
            @service.stub(:display_installed_extensions, nil) do
              @service.restore!(backup_file)

              logs = @logger.instance_variable_get(:@logdev).dev.string
              assert_includes logs, "pg_restore not available, falling back to psql"
              assert_includes logs, "Database restore completed successfully"
            end
          end
        end
      end
    end

    def test_handles_restore_failure
      backup_file = File.join(@test_dir, "backup.tar")
      FileUtils.touch(backup_file)

      @service.stub(:pg_restore_available?, true) do
        @service.stub(:recreate_database, nil) do
          @service.stub(:execute_pg_restore, proc { raise "Restore failed" }) do
            error = assert_raises(RuntimeError) do
              @service.restore!(backup_file)
            end

            assert_equal "Restore failed", error.message

            logs = @logger.instance_variable_get(:@logdev).dev.string
            assert_includes logs, "Restore failed"
          end
        end
      end
    end

    def test_excludes_tables_during_restore
      backup_file = File.join(@test_dir, "backup.tar")
      FileUtils.touch(backup_file)
      exclude_tables = %w[table1 table2 table3]

      toc_generated = false
      @service.stub(:pg_restore_available?, true) do
        @service.stub(
          :generate_filtered_toc,
          proc { |_file, tables|
            toc_generated = true
            assert_equal exclude_tables, tables
            File.join(@test_dir, "toc.list")
          }
        ) do
          @service.stub(:recreate_database, nil) do
            @service.stub(:execute_pg_restore, nil) do
              @service.stub(:run_migrations, nil) do
                @service.stub(:display_installed_extensions, nil) do
                  @service.restore!(backup_file, exclude_tables: exclude_tables)

                  assert toc_generated, "Expected TOC to be generated with excluded tables"

                  logs = @logger.instance_variable_get(:@logdev).dev.string
                  assert_includes logs, "Excluded tables: table1, table2, table3"
                end
              end
            end
          end
        end
      end
    end

    def test_handles_empty_exclude_tables
      backup_file = File.join(@test_dir, "backup.tar")
      FileUtils.touch(backup_file)
      exclude_tables = []

      toc_generated = false
      @service.stub(:pg_restore_available?, true) do
        @service.stub(
          :generate_filtered_toc,
          proc {
            toc_generated = true
            "should_not_be_called"
          }
        ) do
          @service.stub(:recreate_database, nil) do
            @service.stub(:execute_pg_restore, nil) do
              @service.stub(:run_migrations, nil) do
                @service.stub(:display_installed_extensions, nil) do
                  @service.restore!(backup_file, exclude_tables: exclude_tables)

                  refute toc_generated, "TOC should not be generated when no tables excluded"

                  logs = @logger.instance_variable_get(:@logdev).dev.string
                  refute_includes logs, "Excluded tables:"
                end
              end
            end
          end
        end
      end
    end
  end

  describe "pg_restore_available?" do
    def setup
      super
      stub_rails
      @logger = ActiveSupport::TaggedLogging.new(Logger.new(StringIO.new))
      @database_url = "postgresql://user:pass@localhost/test_db"
      ScalingoStagingSync.configure do |config|
        config.logger = @logger
        config.postgis = false
      end
      @service = ScalingoStagingSync::Services::DatabaseRestoreService.new(@database_url, logger: @logger)
    end

    def test_detects_pg_restore_available
      status = Minitest::Mock.new
      status.expect(:success?, true)

      Open3.stub(:capture3, ["", "", status]) do
        result = @service.send(:pg_restore_available?)
        assert result

        status.verify
      end
    end

    def test_detects_pg_restore_unavailable
      status = Minitest::Mock.new
      status.expect(:success?, false)

      Open3.stub(:capture3, ["", "", status]) do
        result = @service.send(:pg_restore_available?)
        refute result

        status.verify
      end
    end
  end

  describe "execute_pg_restore" do
    def setup
      super
      stub_rails
      @logger = ActiveSupport::TaggedLogging.new(Logger.new(StringIO.new))
      @database_url = "postgresql://user:pass@localhost/test_db"
      ScalingoStagingSync.configure do |config|
        config.logger = @logger
        config.postgis = false
      end
      @service = ScalingoStagingSync::Services::DatabaseRestoreService.new(@database_url, logger: @logger)
    end

    def test_executes_pg_restore_successfully
      backup_file = File.join(@test_dir, "backup.tar")
      toc_file = nil

      status = Minitest::Mock.new
      status.expect(:success?, true)

      @service.stub(:build_pg_restore_command, ["pg_restore", backup_file]) do
        @service.stub(:pg_restore_env, {}) do
          Open3.stub(:capture3, ["output", "", status]) do
            @service.send(:execute_pg_restore, backup_file, toc_file)

            logs = @logger.instance_variable_get(:@logdev).dev.string
            assert_includes logs, "Executing pg_restore command"

            status.verify
          end
        end
      end
    end

    def test_raises_error_on_pg_restore_failure
      backup_file = File.join(@test_dir, "backup.tar")
      toc_file = nil

      status = Minitest::Mock.new
      status.expect(:success?, false)
      status.expect(:exitstatus, 1)
      status.expect(:exitstatus, 1)

      @service.stub(:build_pg_restore_command, ["pg_restore", backup_file]) do
        @service.stub(:pg_restore_env, {}) do
          Open3.stub(:capture3, ["", "error output", status]) do
            error = assert_raises(RuntimeError) do
              @service.send(:execute_pg_restore, backup_file, toc_file)
            end

            assert_includes error.message, "Database restore failed with pg_restore"

            logs = @logger.instance_variable_get(:@logdev).dev.string
            assert_includes logs, "pg_restore failed with exit code"
            assert_includes logs, "Error output: error output"

            status.verify
          end
        end
      end
    end
  end

  describe "slack notifications" do
    def setup
      super
      stub_rails
      @logger = ActiveSupport::TaggedLogging.new(Logger.new(StringIO.new))
      @database_url = "postgresql://user:pass@localhost/test_db"
      ScalingoStagingSync.configure do |config|
        config.logger = @logger
        config.postgis = false
      end
      @service = ScalingoStagingSync::Services::DatabaseRestoreService.new(@database_url, logger: @logger)
    end

    def test_sends_notifications_during_restore
      backup_file = File.join(@test_dir, "backup.tar")
      FileUtils.touch(backup_file)

      notifier_mock = Minitest::Mock.new
      notifier_mock.expect(:restore_step, nil, ["💾 Restauration de la base de données..."])
      notifier_mock.expect(:restore_step, nil, ["🔄 Restauration avec pg_restore"])
      notifier_mock.expect(:restore_step, nil, ["✓ Données restaurées"])
      notifier_mock.expect(:restore_step, nil, ["✅ Base de données restaurée avec succès"])

      @service.instance_variable_set(:@slack_notifier, notifier_mock)

      @service.stub(:pg_restore_available?, true) do
        @service.stub(:recreate_database, nil) do
          @service.stub(:execute_pg_restore, nil) do
            @service.stub(:run_migrations, nil) do
              @service.stub(:display_installed_extensions, nil) do
                @service.restore!(backup_file)

                notifier_mock.verify
              end
            end
          end
        end
      end
    end

    def test_sends_error_notification_on_failure
      backup_file = File.join(@test_dir, "backup.tar")
      FileUtils.touch(backup_file)

      notifier_mock = Minitest::Mock.new
      notifier_mock.expect(:restore_step, nil, ["💾 Restauration de la base de données..."])
      notifier_mock.expect(:restore_step, nil, ["🔄 Restauration avec pg_restore"])
      notifier_mock.expect(:restore_error, nil, ["Échec de la restauration"])

      @service.instance_variable_set(:@slack_notifier, notifier_mock)

      @service.stub(:pg_restore_available?, true) do
        @service.stub(:recreate_database, proc { raise "Database recreation failed" }) do
          assert_raises(RuntimeError) do
            @service.restore!(backup_file)
          end

          notifier_mock.verify
        end
      end
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
        config.postgis = false
      end
      @service = ScalingoStagingSync::Services::DatabaseRestoreService.new(@database_url, logger: @logger)
    end

    def test_logs_restore_progress
      backup_file = File.join(@test_dir, "backup.tar")
      FileUtils.touch(backup_file)

      @service.stub(:pg_restore_available?, true) do
        @service.stub(:recreate_database, nil) do
          @service.stub(:execute_pg_restore, nil) do
            @service.stub(:run_migrations, nil) do
              @service.stub(:display_installed_extensions, nil) do
                @service.restore!(backup_file)

                logs = @logger.instance_variable_get(:@logdev).dev.string
                assert_includes logs, "Starting database restore process"
                assert_includes logs, "Backup file: #{backup_file}"
                assert_includes logs, "Checking available restore methods"
                assert_includes logs, "Running database migrations"
                assert_includes logs, "Checking installed PostgreSQL extensions"
                assert_includes logs, "Database restore completed successfully"
              end
            end
          end
        end
      end
    end

    def test_logs_excluded_tables
      backup_file = File.join(@test_dir, "backup.tar")
      FileUtils.touch(backup_file)
      exclude_tables = %w[sessions temp_data]

      @service.stub(:pg_restore_available?, true) do
        @service.stub(:generate_filtered_toc, File.join(@test_dir, "toc.list")) do
          @service.stub(:recreate_database, nil) do
            @service.stub(:execute_pg_restore, nil) do
              @service.stub(:run_migrations, nil) do
                @service.stub(:display_installed_extensions, nil) do
                  @service.restore!(backup_file, exclude_tables: exclude_tables)

                  logs = @logger.instance_variable_get(:@logdev).dev.string
                  assert_includes logs, "Excluded tables: sessions, temp_data"
                end
              end
            end
          end
        end
      end
    end

    def test_logs_errors_with_backtrace
      backup_file = File.join(@test_dir, "backup.tar")
      FileUtils.touch(backup_file)

      error = StandardError.new("Unexpected error")
      error.set_backtrace(%w[line1 line2 line3])

      @service.stub(:pg_restore_available?, proc { raise error }) do
        assert_raises(StandardError) do
          @service.restore!(backup_file)
        end

        logs = @logger.instance_variable_get(:@logdev).dev.string
        assert_includes logs, "Restore failed: Unexpected error"
        assert_includes logs, "Backtrace:"
      end
    end
  end
end
