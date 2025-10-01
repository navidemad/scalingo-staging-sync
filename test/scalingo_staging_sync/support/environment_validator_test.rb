# frozen_string_literal: true

require "test_helper"

class EnvironmentValidatorTest < Minitest::Test
  class ValidatorTestClass
    include ScalingoStagingSync::Support::EnvironmentValidator

    attr_reader :logger, :database_url, :config

    def initialize(logger, config)
      @logger = logger
      @config = config
      @source_app = "production-app"
      @target_app = "staging-app"
    end
  end

  def setup
    super
    @logger = ActiveSupport::TaggedLogging.new(Logger.new(StringIO.new))
    @rails_env_mock = setup_rails_mock(production: false)
    ScalingoStagingSync.configure do |config|
      config.logger = @logger
      config.production_hostname_patterns = [/prod/i, /production/i]
      config.production_app_name_patterns = [/prod/i, /production/i]
      config.require_confirmation = false
      config.dry_run = false
    end
    @config = ScalingoStagingSync.configuration
    @validator = ValidatorTestClass.new(@logger, @config)
  end

  def setup_rails_mock(production: false, env_name: "test")
    rails = Object.const_set(:Rails, Module.new) unless defined?(Rails)

    env_mock = Class.new do
      attr_reader :production_flag, :env_name

      def initialize(production_flag, env_name)
        @production_flag = production_flag
        @env_name = env_name
      end

      def production?
        @production_flag
      end

      def to_s
        @env_name
      end
    end.new(production, env_name)

    root_mock = Class.new do
      attr_reader :test_dir

      def initialize(test_dir)
        @test_dir = test_dir
      end

      def join(path)
        Pathname.new(File.join(@test_dir, path))
      end
    end.new(@test_dir)

    rails.define_singleton_method(:env) { env_mock }
    rails.define_singleton_method(:root) { root_mock }
    rails.define_singleton_method(:logger) { @logger }

    env_mock
  end

  def teardown
    super
    unstub_rails
  end

  describe "validate_environment!" do
    describe "when all validations pass" do
      def setup
        super
        @logger = ActiveSupport::TaggedLogging.new(Logger.new(StringIO.new))
        @rails_env_mock = setup_rails_mock(production: false)
        ScalingoStagingSync.configure do |config|
          config.logger = @logger
          config.production_hostname_patterns = [/prod/i, /production/i]
          config.production_app_name_patterns = [/prod/i, /production/i]
          config.require_confirmation = false
          config.dry_run = false
        end
        @config = ScalingoStagingSync.configuration
        @validator = ValidatorTestClass.new(@logger, @config)
      end

      def test_successful_validation
        with_env("APP" => "staging-app", "DATABASE_URL" => "postgresql://localhost/test")

        @validator.validate_environment!
        assert_equal "postgresql://localhost/test", @validator.database_url
      end

      def test_validates_with_scalingo_postgresql_url_when_database_url_missing
        with_env(
          "APP" => "staging",
          "DATABASE_URL" => nil,
          "SCALINGO_POSTGRESQL_URL" => "postgresql://localhost/scalingo"
        )

        @validator.validate_environment!
        assert_equal "postgresql://localhost/scalingo", @validator.database_url
      end
    end

    describe "production environment protection" do
      def setup
        super
        @logger = ActiveSupport::TaggedLogging.new(Logger.new(StringIO.new))
        @rails_env_mock = setup_rails_mock(production: false)
        ScalingoStagingSync.configure do |config|
          config.logger = @logger
          config.production_hostname_patterns = [/prod/i, /production/i]
          config.production_app_name_patterns = [/prod/i, /production/i]
          config.require_confirmation = false
          config.dry_run = false
        end
        @config = ScalingoStagingSync.configuration
        @validator = ValidatorTestClass.new(@logger, @config)
      end

      def test_blocks_production_environment
        teardown
        @logger = ActiveSupport::TaggedLogging.new(Logger.new(StringIO.new))
        setup_rails_mock(production: true, env_name: "production")

        with_env("APP" => "staging", "DATABASE_URL" => "postgresql://localhost/test")

        validator = ValidatorTestClass.new(@logger, @config)
        error = assert_raises(ScalingoStagingSync::Support::EnvironmentValidator::ProductionEnvironmentError) do
          validator.validate_environment!
        end
        assert_includes error.message, "Production environment detected"
        assert_includes error.message, "Rails Environment"
      end

      def test_allows_non_production_environments
        with_env("APP" => "staging", "DATABASE_URL" => "postgresql://localhost/test")

        @validator.validate_environment!
      end
    end

    describe "app name validation with patterns" do
      def setup
        super
        @logger = ActiveSupport::TaggedLogging.new(Logger.new(StringIO.new))
        @rails_env_mock = setup_rails_mock(production: false)
        ScalingoStagingSync.configure do |config|
          config.logger = @logger
          config.production_hostname_patterns = [/prod/i, /production/i]
          config.production_app_name_patterns = [/prod/i, /production/i]
          config.require_confirmation = false
          config.dry_run = false
        end
        @config = ScalingoStagingSync.configuration
        @validator = ValidatorTestClass.new(@logger, @config)
      end

      def test_blocks_app_names_matching_production_patterns
        with_env("DATABASE_URL" => "postgresql://localhost/test")

        %w[production prod-app app-prod my-production-app PRODUCTION PROD].each do |app_name|
          with_env("APP" => app_name)

          validator = ValidatorTestClass.new(@logger, @config)
          error = assert_raises(ScalingoStagingSync::Support::EnvironmentValidator::ProductionEnvironmentError) do
            validator.validate_environment!
          end
          assert_includes error.message, "Production environment detected"
          assert_includes error.message, "APP Environment Variable"
        end
      end

      def test_allows_safe_app_names
        with_env("DATABASE_URL" => "postgresql://localhost/test")

        %w[staging demo development test-app review-app-123 feature-branch].each do |app_name|
          with_env("APP" => app_name)

          validator = ValidatorTestClass.new(@logger, @config)
          validator.validate_environment!
        end
      end

      def test_allows_empty_app_name
        with_env("APP" => nil, "DATABASE_URL" => "postgresql://localhost/test")

        @validator.validate_environment!
      end

      def test_respects_custom_app_name_patterns
        with_env("DATABASE_URL" => "postgresql://localhost/test")

        @config.production_app_name_patterns = [/^live-/i, /master$/i]

        %w[live-app app-master LIVE-SERVICE].each do |app_name|
          with_env("APP" => app_name)

          validator = ValidatorTestClass.new(@logger, @config)
          error = assert_raises(ScalingoStagingSync::Support::EnvironmentValidator::ProductionEnvironmentError) do
            validator.validate_environment!
          end
          assert_includes error.message, "APP Environment Variable"
        end

        %w[prod-app production].each do |app_name|
          with_env("APP" => app_name)

          validator = ValidatorTestClass.new(@logger, @config)
          validator.validate_environment!
        end
      end
    end

    describe "database URL hostname validation" do
      def setup
        super
        @logger = ActiveSupport::TaggedLogging.new(Logger.new(StringIO.new))
        @rails_env_mock = setup_rails_mock(production: false)
        ScalingoStagingSync.configure do |config|
          config.logger = @logger
          config.production_hostname_patterns = [/prod/i, /production/i]
          config.production_app_name_patterns = [/prod/i, /production/i]
          config.require_confirmation = false
          config.dry_run = false
        end
        @config = ScalingoStagingSync.configuration
        @validator = ValidatorTestClass.new(@logger, @config)
      end

      def test_blocks_production_hostnames_in_database_url
        with_env("APP" => "staging")

        [
          "postgresql://prod-db.example.com/test",
          "postgres://production.database.com/test",
          "postgresql://user:pass@PROD-SERVER:5432/test"
        ].each do |url|
          with_env("DATABASE_URL" => url)

          validator = ValidatorTestClass.new(@logger, @config)
          error = assert_raises(ScalingoStagingSync::Support::EnvironmentValidator::ProductionEnvironmentError) do
            validator.validate_environment!
          end
          assert_includes error.message, "DATABASE_URL Hostname"
        end
      end

      def test_blocks_production_hostnames_in_scalingo_postgresql_url
        with_env("APP" => "staging", "DATABASE_URL" => nil)

        [
          "postgresql://prod-db.scalingo.com/test",
          "postgres://production.scalingo-dbs.com/test"
        ].each do |url|
          with_env("SCALINGO_POSTGRESQL_URL" => url)

          validator = ValidatorTestClass.new(@logger, @config)
          error = assert_raises(ScalingoStagingSync::Support::EnvironmentValidator::ProductionEnvironmentError) do
            validator.validate_environment!
          end
          assert_includes error.message, "SCALINGO_POSTGRESQL_URL Hostname"
        end
      end

      def test_allows_safe_database_hostnames
        with_env("APP" => "staging")

        [
          "postgresql://staging-db.example.com/test",
          "postgres://localhost/test",
          "postgresql://demo.database.com/test",
          "postgres://review-app.scalingo-dbs.com/test"
        ].each do |url|
          with_env("DATABASE_URL" => url)

          validator = ValidatorTestClass.new(@logger, @config)
          validator.validate_environment!
        end
      end

      def test_handles_invalid_urls_gracefully
        with_env("APP" => "staging", "DATABASE_URL" => "not-a-valid-url")

        @validator.validate_environment!
      end

      def test_respects_custom_hostname_patterns
        with_env("APP" => "staging")

        @config.production_hostname_patterns = [/^master\./i, /\.live\./i]

        [
          "postgresql://master.db.com/test",
          "postgres://db.live.example.com/test"
        ].each do |url|
          with_env("DATABASE_URL" => url)

          validator = ValidatorTestClass.new(@logger, @config)
          error = assert_raises(ScalingoStagingSync::Support::EnvironmentValidator::ProductionEnvironmentError) do
            validator.validate_environment!
          end
          assert_includes error.message, "DATABASE_URL Hostname"
        end

        with_env("DATABASE_URL" => "postgresql://prod.db.com/test")
        validator = ValidatorTestClass.new(@logger, @config)
        validator.validate_environment!
      end
    end

    describe "multiple validation failures" do
      def setup
        super
        @logger = ActiveSupport::TaggedLogging.new(Logger.new(StringIO.new))
        @rails_env_mock = setup_rails_mock(production: false)
        ScalingoStagingSync.configure do |config|
          config.logger = @logger
          config.production_hostname_patterns = [/prod/i, /production/i]
          config.production_app_name_patterns = [/prod/i, /production/i]
          config.require_confirmation = false
          config.dry_run = false
        end
        @config = ScalingoStagingSync.configuration
        @validator = ValidatorTestClass.new(@logger, @config)
      end

      def test_reports_multiple_failures
        with_env(
          "APP" => "production-app",
          "DATABASE_URL" => "postgresql://prod-db.example.com/test",
          "SCALINGO_POSTGRESQL_URL" => "postgresql://production.scalingo.com/test"
        )

        validator = ValidatorTestClass.new(@logger, @config)
        error = assert_raises(ScalingoStagingSync::Support::EnvironmentValidator::ProductionEnvironmentError) do
          validator.validate_environment!
        end

        assert_includes error.message, "APP Environment Variable"
        assert_includes error.message, "DATABASE_URL Hostname"
        assert_includes error.message, "SCALINGO_POSTGRESQL_URL Hostname"
      end

      def test_reports_all_failures_including_database_url
        with_env("APP" => "prod-app", "DATABASE_URL" => nil, "SCALINGO_POSTGRESQL_URL" => nil)

        validator = ValidatorTestClass.new(@logger, @config)
        error = assert_raises(ScalingoStagingSync::Support::EnvironmentValidator::ProductionEnvironmentError) do
          validator.validate_environment!
        end

        assert_includes error.message, "APP Environment Variable"
        assert_includes error.message, "Database URL"
      end
    end

    describe "interactive confirmation" do
      def setup
        super
        @logger = ActiveSupport::TaggedLogging.new(Logger.new(StringIO.new))
        @rails_env_mock = setup_rails_mock(production: false)
        ScalingoStagingSync.configure do |config|
          config.logger = @logger
          config.production_hostname_patterns = [/prod/i, /production/i]
          config.production_app_name_patterns = [/prod/i, /production/i]
          config.dry_run = false
        end
        @config = ScalingoStagingSync.configuration
        @validator = ValidatorTestClass.new(@logger, @config)
      end

      def test_requires_confirmation_when_configured
        @config.require_confirmation = true
        with_env("APP" => "staging", "DATABASE_URL" => "postgresql://localhost/test", "CI" => nil)

        $stdin = StringIO.new("staging-app\n")

        @validator.validate_environment!
      ensure
        $stdin = STDIN
      end

      def test_fails_with_wrong_confirmation
        @config.require_confirmation = true
        with_env("APP" => "staging", "DATABASE_URL" => "postgresql://localhost/test", "CI" => nil)

        $stdin = StringIO.new("wrong-app\n")

        error = assert_raises(ScalingoStagingSync::Support::EnvironmentValidator::ProductionEnvironmentError) do
          @validator.validate_environment!
        end
        assert_includes error.message, "User confirmation failed"
      ensure
        $stdin = STDIN
      end

      def test_skips_confirmation_in_ci_environment
        @config.require_confirmation = true
        with_env("APP" => "staging", "DATABASE_URL" => "postgresql://localhost/test", "CI" => "true")

        @validator.validate_environment!
      end

      def test_skips_confirmation_when_disabled
        @config.require_confirmation = false
        with_env("APP" => "staging", "DATABASE_URL" => "postgresql://localhost/test")

        @validator.validate_environment!
      end
    end

    describe "dry run mode" do
      def setup
        super
        @logger = ActiveSupport::TaggedLogging.new(Logger.new(StringIO.new))
        @rails_env_mock = setup_rails_mock(production: false)
        ScalingoStagingSync.configure do |config|
          config.logger = @logger
          config.production_hostname_patterns = [/prod/i, /production/i]
          config.production_app_name_patterns = [/prod/i, /production/i]
          config.require_confirmation = false
        end
        @config = ScalingoStagingSync.configuration
        @validator = ValidatorTestClass.new(@logger, @config)
      end

      def test_logs_dry_run_warning
        @config.dry_run = true
        with_env("APP" => "staging", "DATABASE_URL" => "postgresql://localhost/test")

        string_io = StringIO.new
        logger = ActiveSupport::TaggedLogging.new(Logger.new(string_io))
        validator = ValidatorTestClass.new(logger, @config)

        validator.validate_environment!

        logs = string_io.string
        assert_includes logs, "DRY RUN MODE ENABLED"
        assert_includes logs, "operations will be logged but NOT executed"
      end
    end

    describe "logging behavior" do
      def setup
        super
        @logger = ActiveSupport::TaggedLogging.new(Logger.new(StringIO.new))
        @rails_env_mock = setup_rails_mock(production: false)
        ScalingoStagingSync.configure do |config|
          config.logger = @logger
          config.production_hostname_patterns = [/prod/i, /production/i]
          config.production_app_name_patterns = [/prod/i, /production/i]
          config.require_confirmation = false
          config.dry_run = false
        end
        @config = ScalingoStagingSync.configuration
        @validator = ValidatorTestClass.new(@logger, @config)
      end

      def test_logs_detailed_environment_info
        unstub_rails
        setup_rails_mock(production: false, env_name: "staging")
        with_env("APP" => "staging", "DATABASE_URL" => "postgresql://localhost/test")

        string_io = StringIO.new
        logger = ActiveSupport::TaggedLogging.new(Logger.new(string_io))
        validator = ValidatorTestClass.new(logger, @config)

        validator.validate_environment!

        logs = string_io.string
        assert_includes logs, "Environment Details:"
        assert_includes logs, "Rails Environment: staging"
        assert_includes logs, "APP (Target): staging"
        assert_includes logs, "Source App: production-app"
        assert_includes logs, "CI Environment: false"
        assert_includes logs, "Dry Run Mode: false"
        assert_includes logs, "All safety checks passed"
      end

      def test_logs_failed_checks_with_remediation
        with_env("APP" => "prod-app", "DATABASE_URL" => "postgresql://localhost/test")

        string_io = StringIO.new
        logger = ActiveSupport::TaggedLogging.new(Logger.new(string_io))
        validator = ValidatorTestClass.new(logger, @config)

        assert_raises(ScalingoStagingSync::Support::EnvironmentValidator::ProductionEnvironmentError) do
          validator.validate_environment!
        end

        logs = string_io.string
        assert_includes logs, "PRODUCTION ENVIRONMENT DETECTED - OPERATION BLOCKED"
        assert_includes logs, "APP Environment Variable"
        assert_includes logs, "Remediation:"
        assert_includes logs, "production_app_name_patterns"
      end
    end

    describe "edge cases" do
      def setup
        super
        ScalingoStagingSync.configure do |config|
          config.logger = @logger
          config.production_hostname_patterns = [/prod/i, /production/i]
          config.production_app_name_patterns = [/prod/i, /production/i]
          config.require_confirmation = false
          config.dry_run = false
        end
        @config = ScalingoStagingSync.configuration
      end

      def test_handles_nil_app_gracefully
        with_env("APP" => nil, "DATABASE_URL" => "postgresql://localhost/test")

        validator = ValidatorTestClass.new(@logger, @config)
        validator.validate_environment!
      end

      def test_handles_empty_string_app
        with_env("APP" => "", "DATABASE_URL" => "postgresql://localhost/test")

        validator = ValidatorTestClass.new(@logger, @config)
        validator.validate_environment!
      end

      def test_requires_database_url
        with_env("APP" => "staging", "DATABASE_URL" => nil, "SCALINGO_POSTGRESQL_URL" => nil)

        string_io = StringIO.new
        logger = ActiveSupport::TaggedLogging.new(Logger.new(string_io))
        validator = ValidatorTestClass.new(logger, @config)

        error = assert_raises(ScalingoStagingSync::Support::EnvironmentValidator::ProductionEnvironmentError) do
          validator.validate_environment!
        end
        assert_includes error.message, "Database URL"

        logs = string_io.string
        assert_includes logs, "Neither DATABASE_URL nor SCALINGO_POSTGRESQL_URL is set"
      end

      def test_prefers_database_url_over_scalingo_url
        with_env(
          "APP" => "staging",
          "DATABASE_URL" => "postgresql://localhost/primary",
          "SCALINGO_POSTGRESQL_URL" => "postgresql://localhost/scalingo"
        )

        validator = ValidatorTestClass.new(@logger, @config)
        validator.validate_environment!
        assert_equal "postgresql://localhost/primary", validator.database_url
      end
    end
  end
end
