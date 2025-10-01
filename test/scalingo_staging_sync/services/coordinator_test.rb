# frozen_string_literal: true

require "test_helper"

class CoordinatorTest < Minitest::Test
  def setup
    super
    stub_rails
    @logger = ActiveSupport::TaggedLogging.new(Logger.new(StringIO.new))

    ScalingoStagingSync.configure do |config|
      config.clone_source_scalingo_app_name = "production-app"
      config.logger = @logger
      config.temp_dir = @test_dir
      config.slack_enabled = false
      config.exclude_tables = ["audit_logs"]
      config.seeds_file_path = nil
      config.production_hostname_patterns = [/prod/i, /production/i]
      config.production_app_name_patterns = [/prod/i, /production/i]
      config.dry_run = false
    end

    @coordinator = ScalingoStagingSync::Services::Coordinator.new(logger: @logger)
  end

  def teardown
    super
    unstub_rails
  end

  describe "initialization" do
    def setup
      super
      stub_rails
      @logger = ActiveSupport::TaggedLogging.new(Logger.new(StringIO.new))

      with_env("APP" => "test-app")

      ScalingoStagingSync.configure do |config|
        config.clone_source_scalingo_app_name = "production-app"
        config.logger = @logger
        config.temp_dir = @test_dir
        config.slack_enabled = false
        config.exclude_tables = ["audit_logs"]
        config.seeds_file_path = nil
        config.production_hostname_patterns = [/prod/i, /production/i]
        config.production_app_name_patterns = [/prod/i, /production/i]
        config.dry_run = false
      end
    end

    def test_initializes_with_configuration
      coordinator = ScalingoStagingSync::Services::Coordinator.new(logger: @logger)

      assert_equal "production-app", coordinator.instance_variable_get(:@source_app)
      refute_nil coordinator.instance_variable_get(:@logger)
      refute_nil coordinator.instance_variable_get(:@slack_notifier)
    end

    def test_uses_env_app_for_target
      with_env("APP" => "staging-app")

      coordinator = ScalingoStagingSync::Services::Coordinator.new(logger: @logger)
      assert_equal "staging-app", coordinator.instance_variable_get(:@target_app)
    end

    def test_raises_without_app_env
      with_env("APP" => nil)

      error = assert_raises(ArgumentError) do
        ScalingoStagingSync::Services::Coordinator.new(logger: @logger)
      end
      assert_includes error.message, "ENV['APP'] is required"
    end
  end

  describe "execute!" do
    def setup
      super
      stub_rails
      @logger = ActiveSupport::TaggedLogging.new(Logger.new(StringIO.new))

      with_env("APP" => "staging", "DATABASE_URL" => "postgresql://localhost/test")

      ScalingoStagingSync.configure do |config|
        config.clone_source_scalingo_app_name = "production-app"
        config.logger = @logger
        config.temp_dir = @test_dir
        config.slack_enabled = false
        config.exclude_tables = ["audit_logs"]
        config.seeds_file_path = nil
        config.production_hostname_patterns = [/prod/i, /production/i]
        config.production_app_name_patterns = [/prod/i, /production/i]
        config.dry_run = false
      end

      @coordinator = ScalingoStagingSync::Services::Coordinator.new(logger: @logger)
    end

    def test_successful_sync_flow
      env_mock = setup_rails_mock(production: false)
      env_mock.stub(:production?, false) do
        # Mock the service calls
        backup_service = Minitest::Mock.new
        backup_service.expect(:download_and_extract!, "/tmp/backup.tar.gz")

        restore_service = Minitest::Mock.new
        def restore_service.restore!(*_args, **_kwargs) = true

        anonymizer_service = Minitest::Mock.new
        anonymizer_service.expect(:anonymize!, true)

        slack_service = Minitest::Mock.new
        5.times { slack_service.expect(:coordinator_step, true, [Object]) }
        slack_service.expect(:coordinator_step, true, ["⚠️ Aucun fichier de seeds configuré"])
        slack_service.expect(:notify_success, true, [Numeric, String, String])

        # Stub service instantiation
        ScalingoStagingSync::Services::DatabaseBackupService.stub(:new, backup_service) do
          ScalingoStagingSync::Services::DatabaseRestoreService.stub(:new, restore_service) do
            ScalingoStagingSync::Services::DatabaseAnonymizerService.stub(:new, anonymizer_service) do
              @coordinator.instance_variable_set(:@slack_notifier, slack_service)

              @coordinator.execute!

              backup_service.verify
              restore_service.verify
              anonymizer_service.verify
              slack_service.verify
            end
          end
        end
      end
    end

    def test_blocks_production_environment
      env_mock = setup_rails_mock(production: true)
      env_mock.stub(:production?, true) do
        error = assert_raises(ScalingoStagingSync::Support::EnvironmentValidator::ProductionEnvironmentError) do
          @coordinator.execute!
        end
        assert_includes error.message, "Production environment detected"
      end
    end

    def test_blocks_production_app_names
      with_env("APP" => "prod-app")
      env_mock = setup_rails_mock(production: false)
      env_mock.stub(:production?, false) do
        error = assert_raises(ScalingoStagingSync::Support::EnvironmentValidator::ProductionEnvironmentError) do
          @coordinator.execute!
        end
        assert_includes error.message, "APP Environment Variable"
      end
    end

    def test_handles_errors_gracefully
      env_mock = setup_rails_mock(production: false)
      env_mock.stub(:production?, false) do
        # Mock backup service to raise an error
        backup_service = Minitest::Mock.new
        def backup_service.download_and_extract!(*)
          raise "Download failed"
        end

        slack_service = Minitest::Mock.new
        2.times { slack_service.expect(:coordinator_step, true, [Object]) }
        slack_service.expect(:notify_failure, true, [String, String])

        ScalingoStagingSync::Services::DatabaseBackupService.stub(:new, backup_service) do
          @coordinator.instance_variable_set(:@slack_notifier, slack_service)

          error = assert_raises(RuntimeError) do
            @coordinator.execute!
          end
          assert_equal "Download failed", error.message

          slack_service.verify
        end
      end
    end
  end

  describe "dry run mode" do
    def setup
      super
      stub_rails
      @logger = ActiveSupport::TaggedLogging.new(Logger.new(StringIO.new))

      with_env("APP" => "staging", "DATABASE_URL" => "postgresql://localhost/test")

      ScalingoStagingSync.configure do |config|
        config.clone_source_scalingo_app_name = "production-app"
        config.logger = @logger
        config.temp_dir = @test_dir
        config.slack_enabled = false
        config.exclude_tables = ["audit_logs"]
        config.seeds_file_path = nil
        config.production_hostname_patterns = [/prod/i, /production/i]
        config.production_app_name_patterns = [/prod/i, /production/i]
        config.dry_run = false
      end

      @coordinator = ScalingoStagingSync::Services::Coordinator.new(logger: @logger)
    end

    def test_performs_dry_run_without_actual_operations
      ScalingoStagingSync.configuration.dry_run = true

      env_mock = setup_rails_mock(production: false)
      env_mock.stub(:production?, false) do
        slack_service = Minitest::Mock.new
        slack_service.expect(:coordinator_step, true, [Object])
        slack_service.expect(:notify_success, true, [Numeric, String, String])

        @coordinator.instance_variable_set(:@slack_notifier, slack_service)

        # In dry run, no actual services should be called
        @coordinator.execute!

        slack_service.verify

        # Check logs for dry run messages
        logs = @logger.instance_variable_get(:@logdev).dev.string
        assert_includes logs, "[DRY RUN]"
        assert_includes logs, "Would download backup"
        assert_includes logs, "Would restore database"
        assert_includes logs, "Would anonymize data"
        assert_includes logs, "Configuration validated successfully"
      end
    end
  end

  describe "seeds execution" do
    def setup
      super
      stub_rails
      @logger = ActiveSupport::TaggedLogging.new(Logger.new(StringIO.new))

      with_env("APP" => "staging", "DATABASE_URL" => "postgresql://localhost/test")

      ScalingoStagingSync.configure do |config|
        config.clone_source_scalingo_app_name = "production-app"
        config.logger = @logger
        config.temp_dir = @test_dir
        config.slack_enabled = false
        config.exclude_tables = ["audit_logs"]
        config.seeds_file_path = nil
        config.production_hostname_patterns = [/prod/i, /production/i]
        config.production_app_name_patterns = [/prod/i, /production/i]
        config.dry_run = false
      end

      @coordinator = ScalingoStagingSync::Services::Coordinator.new(logger: @logger)
    end

    def test_runs_seeds_when_configured
      seeds_file = File.join(@test_dir, "demo_seeds.rb")
      File.write(seeds_file, "puts 'Seeds executed'")

      ScalingoStagingSync.configuration.seeds_file_path = seeds_file

      env_mock = setup_rails_mock(production: false)
      env_mock.stub(:production?, false) do
        # Mock services
        backup_service = Minitest::Mock.new
        backup_service.expect(:download_and_extract!, "/tmp/backup.tar.gz")

        restore_service = Minitest::Mock.new
        def restore_service.restore!(*_args, **_kwargs) = true

        anonymizer_service = Minitest::Mock.new
        anonymizer_service.expect(:anonymize!, true)

        slack_service = Minitest::Mock.new
        5.times { slack_service.expect(:coordinator_step, true, [Object]) }
        slack_service.expect(:coordinator_step, true, ["✓ Comptes de test créés"])
        slack_service.expect(:notify_success, true, [Numeric, String, String])

        ScalingoStagingSync::Services::DatabaseBackupService.stub(:new, backup_service) do
          ScalingoStagingSync::Services::DatabaseRestoreService.stub(:new, restore_service) do
            ScalingoStagingSync::Services::DatabaseAnonymizerService.stub(:new, anonymizer_service) do
              @coordinator.instance_variable_set(:@slack_notifier, slack_service)

              output = capture_subprocess_io do
                @coordinator.execute!
              end

              assert_includes output[0], "Seeds executed"

              backup_service.verify
              restore_service.verify
              anonymizer_service.verify
              slack_service.verify
            end
          end
        end
      end
    end

    def test_skips_seeds_when_not_configured
      ScalingoStagingSync.configuration.seeds_file_path = nil

      env_mock = setup_rails_mock(production: false)
      env_mock.stub(:production?, false) do
        # Mock services
        backup_service = Minitest::Mock.new
        backup_service.expect(:download_and_extract!, "/tmp/backup.tar.gz")

        restore_service = Minitest::Mock.new
        def restore_service.restore!(*_args, **_kwargs) = true

        anonymizer_service = Minitest::Mock.new
        anonymizer_service.expect(:anonymize!, true)

        slack_service = Minitest::Mock.new
        5.times { slack_service.expect(:coordinator_step, true, [Object]) }
        slack_service.expect(:coordinator_step, true, ["⚠️ Aucun fichier de seeds configuré"])
        slack_service.expect(:notify_success, true, [Numeric, String, String])

        ScalingoStagingSync::Services::DatabaseBackupService.stub(:new, backup_service) do
          ScalingoStagingSync::Services::DatabaseRestoreService.stub(:new, restore_service) do
            ScalingoStagingSync::Services::DatabaseAnonymizerService.stub(:new, anonymizer_service) do
              @coordinator.instance_variable_set(:@slack_notifier, slack_service)

              @coordinator.execute!

              logs = @logger.instance_variable_get(:@logdev).dev.string
              assert_includes logs, "No seeds file configured"

              backup_service.verify
              restore_service.verify
              anonymizer_service.verify
              slack_service.verify
            end
          end
        end
      end
    end

    def test_handles_missing_seeds_file
      ScalingoStagingSync.configuration.seeds_file_path = "/nonexistent/seeds.rb"

      env_mock = setup_rails_mock(production: false)
      env_mock.stub(:production?, false) do
        # Mock services
        backup_service = Minitest::Mock.new
        backup_service.expect(:download_and_extract!, "/tmp/backup.tar.gz")

        restore_service = Minitest::Mock.new
        def restore_service.restore!(*_args, **_kwargs) = true

        anonymizer_service = Minitest::Mock.new
        anonymizer_service.expect(:anonymize!, true)

        slack_service = Minitest::Mock.new
        5.times { slack_service.expect(:coordinator_step, true, [Object]) }
        slack_service.expect(:coordinator_step, true, ["⚠️ Fichier seeds configuré introuvable"])
        slack_service.expect(:notify_success, true, [Numeric, String, String])

        ScalingoStagingSync::Services::DatabaseBackupService.stub(:new, backup_service) do
          ScalingoStagingSync::Services::DatabaseRestoreService.stub(:new, restore_service) do
            ScalingoStagingSync::Services::DatabaseAnonymizerService.stub(:new, anonymizer_service) do
              @coordinator.instance_variable_set(:@slack_notifier, slack_service)

              @coordinator.execute!

              logs = @logger.instance_variable_get(:@logdev).dev.string
              assert_includes logs, "Configured seeds file not found"

              backup_service.verify
              restore_service.verify
              anonymizer_service.verify
              slack_service.verify
            end
          end
        end
      end
    end
  end

  describe "logging" do
    def setup
      super
      stub_rails
      @logger = ActiveSupport::TaggedLogging.new(Logger.new(StringIO.new))

      with_env("APP" => "staging", "DATABASE_URL" => "postgresql://localhost/test")

      ScalingoStagingSync.configure do |config|
        config.clone_source_scalingo_app_name = "production-app"
        config.logger = @logger
        config.temp_dir = @test_dir
        config.slack_enabled = false
        config.exclude_tables = ["audit_logs"]
        config.seeds_file_path = nil
        config.production_hostname_patterns = [/prod/i, /production/i]
        config.production_app_name_patterns = [/prod/i, /production/i]
        config.dry_run = false
      end

      @coordinator = ScalingoStagingSync::Services::Coordinator.new(logger: @logger)
    end

    def test_logs_each_step
      env_mock = setup_rails_mock(production: false)
      env_mock.stub(:production?, false) do
        # Mock services
        backup_service = Minitest::Mock.new
        backup_service.expect(:download_and_extract!, "/tmp/backup.tar.gz")

        restore_service = Minitest::Mock.new
        def restore_service.restore!(*_args, **_kwargs) = true

        anonymizer_service = Minitest::Mock.new
        anonymizer_service.expect(:anonymize!, true)

        slack_service = Minitest::Mock.new
        5.times { slack_service.expect(:coordinator_step, true, [Object]) }
        slack_service.expect(:coordinator_step, true, ["⚠️ Aucun fichier de seeds configuré"])
        slack_service.expect(:notify_success, true, [Numeric, String, String])

        ScalingoStagingSync::Services::DatabaseBackupService.stub(:new, backup_service) do
          ScalingoStagingSync::Services::DatabaseRestoreService.stub(:new, restore_service) do
            ScalingoStagingSync::Services::DatabaseAnonymizerService.stub(:new, anonymizer_service) do
              @coordinator.instance_variable_set(:@slack_notifier, slack_service)

              @coordinator.execute!

              logs = @logger.instance_variable_get(:@logdev).dev.string
              assert_includes logs, "Starting staging sync process"
              assert_includes logs, "Source: production-app"
              assert_includes logs, "Target: staging"
              assert_includes logs, "Step 1: Downloading backup"
              assert_includes logs, "Step 2: Restoring database"
              assert_includes logs, "Step 3: Anonymizing data"
              assert_includes logs, "Step 4: Running staging seeds"
              assert_includes logs, "Staging sync completed successfully"

              backup_service.verify
              restore_service.verify
              anonymizer_service.verify
              slack_service.verify
            end
          end
        end
      end
    end

    def test_uses_tagged_logging
      env_mock = setup_rails_mock(production: false)
      env_mock.stub(:production?, false) do
        # Track if tagged was called
        tagged_called = false
        tagged_tag = nil

        # Create a logger with tagged method
        logger_io = StringIO.new
        logger = ActiveSupport::TaggedLogging.new(Logger.new(logger_io))

        # Wrap the tagged method to track calls
        original_tagged = logger.method(:tagged)
        logger.define_singleton_method(:tagged) do |*tags, &block|
          tagged_called = true
          tagged_tag = tags.first
          original_tagged.call(*tags, &block)
        end

        coordinator = ScalingoStagingSync::Services::Coordinator.new(logger: logger)

        # Mock services
        backup_service = Minitest::Mock.new
        backup_service.expect(:download_and_extract!, "/tmp/backup.tar.gz")

        restore_service = Minitest::Mock.new
        def restore_service.restore!(*_args, **_kwargs) = true

        anonymizer_service = Minitest::Mock.new
        anonymizer_service.expect(:anonymize!, true)

        slack_service = Minitest::Mock.new
        5.times { slack_service.expect(:coordinator_step, true, [Object]) }
        slack_service.expect(:coordinator_step, true, ["⚠️ Aucun fichier de seeds configuré"])
        slack_service.expect(:notify_success, true, [Numeric, String, String])

        ScalingoStagingSync::Services::DatabaseBackupService.stub(:new, backup_service) do
          ScalingoStagingSync::Services::DatabaseRestoreService.stub(:new, restore_service) do
            ScalingoStagingSync::Services::DatabaseAnonymizerService.stub(:new, anonymizer_service) do
              coordinator.instance_variable_set(:@slack_notifier, slack_service)

              coordinator.execute!

              assert tagged_called, "Logger.tagged should have been called"
              assert_equal "SCALINGO_STAGING_SYNC", tagged_tag

              backup_service.verify
              restore_service.verify
              anonymizer_service.verify
              slack_service.verify
            end
          end
        end
      end
    end
  end

  describe "excluded tables configuration" do
    def setup
      super
      stub_rails
      @logger = ActiveSupport::TaggedLogging.new(Logger.new(StringIO.new))

      with_env("APP" => "staging", "DATABASE_URL" => "postgresql://localhost/test")

      ScalingoStagingSync.configure do |config|
        config.clone_source_scalingo_app_name = "production-app"
        config.logger = @logger
        config.temp_dir = @test_dir
        config.slack_enabled = false
        config.exclude_tables = ["audit_logs"]
        config.seeds_file_path = nil
        config.production_hostname_patterns = [/prod/i, /production/i]
        config.production_app_name_patterns = [/prod/i, /production/i]
        config.dry_run = false
      end

      @coordinator = ScalingoStagingSync::Services::Coordinator.new(logger: @logger)
    end

    def test_passes_exclude_tables_to_restore_service
      ScalingoStagingSync.configuration.exclude_tables = %w[logs sessions cache]

      env_mock = setup_rails_mock(production: false)
      env_mock.stub(:production?, false) do
        # Mock services
        backup_service = Minitest::Mock.new
        backup_service.expect(:download_and_extract!, "/tmp/backup.tar.gz")

        restore_service = Object.new
        restore_service.instance_eval do
          @restore_file = nil
          @restore_options = nil

          def restore!(file, options={})
            @restore_file = file
            @restore_options = options
            true
          end
        end

        anonymizer_service = Minitest::Mock.new
        anonymizer_service.expect(:anonymize!, true)

        slack_service = Minitest::Mock.new
        5.times { slack_service.expect(:coordinator_step, true, [Object]) }
        slack_service.expect(:coordinator_step, true, ["⚠️ Aucun fichier de seeds configuré"])
        slack_service.expect(:notify_success, true, [Numeric, String, String])

        ScalingoStagingSync::Services::DatabaseBackupService.stub(:new, backup_service) do
          ScalingoStagingSync::Services::DatabaseRestoreService.stub(:new, restore_service) do
            ScalingoStagingSync::Services::DatabaseAnonymizerService.stub(:new, anonymizer_service) do
              @coordinator.instance_variable_set(:@slack_notifier, slack_service)

              @coordinator.execute!

              assert_equal "/tmp/backup.tar.gz", restore_service.instance_variable_get(:@restore_file)
              assert_equal %w[logs sessions cache], restore_service.instance_variable_get(:@restore_options)[:exclude_tables]

              backup_service.verify
              anonymizer_service.verify
              slack_service.verify
            end
          end
        end
      end
    end
  end
end
