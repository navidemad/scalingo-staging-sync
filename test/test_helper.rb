# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "scalingo_staging_sync"

require "minitest/autorun"
require "minitest/mock"
require "logger"
require "tmpdir"
require "fileutils"
require "pg"
require "active_support/tagged_logging"
require "active_support/testing/time_helpers"

# Suppress noisy warnings in tests
module WarningFilter
  def warn(message)
    # Suppress net-http Content-Type warnings
    return if message.include?("net/http: Content-Type did not set")
    # Suppress Minitest 6 deprecation warnings
    return if message.include?("This will fail in Minitest 6")

    super
  end
end

Warning.extend(WarningFilter) if defined?(Warning)

# Load support files
Dir[File.expand_path("support/**/*.rb", __dir__)].each { |rb| require(rb) }

# Test helper module for common test utilities
module TestHelpers
  include ActiveSupport::Testing::TimeHelpers

  def setup
    super
    # Reset configuration before each test
    ScalingoStagingSync.reset_configuration!

    # Set up test environment variables
    @original_env = {}
    @test_dir = Dir.mktmpdir("scalingo_staging_sync_test")
    @logger = ActiveSupport::TaggedLogging.new(Logger.new(StringIO.new))

    # Set default SCALINGO_API_TOKEN for tests
    with_env("SCALINGO_API_TOKEN" => "test-token-123")

    # Freeze time
    freeze_time
  end

  def teardown
    # Unfreeze time
    travel_back

    # Clean up test directory
    FileUtils.rm_rf(@test_dir) if @test_dir&.then { |dir| File.exist?(dir) }

    # Restore original environment variables
    @original_env&.each do |key, value|
      if value.nil?
        ENV.delete(key)
      else
        ENV[key] = value
      end
    end

    super
  end

  def with_env(env_vars)
    @original_env ||= {}
    env_vars.each do |key, value|
      @original_env[key] = ENV.fetch(key, nil) unless @original_env.key?(key)
      ENV[key] = value
    end
  end

  def stub_scalingo_client
    client_mock = Minitest::Mock.new
    osc_fr1_mock = Minitest::Mock.new
    addons_mock = Minitest::Mock.new

    client_mock.expect(:authenticate_with, true, [{ access_token: "test_token" }])
    client_mock.expect(:osc_fr1, osc_fr1_mock)
    osc_fr1_mock.expect(:addons, addons_mock)

    client_mock
  end

  def stub_rails
    unstub_rails if defined?(Rails)
    rails = Object.const_set(:Rails, Module.new)

    env_mock = Class.new do
      def production?
        false
      end

      def to_s
        "test"
      end
    end.new

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

    rails
  end

  def setup_rails_mock(production: false, env_name: nil)
    unstub_rails if defined?(Rails)
    rails = Object.const_set(:Rails, Module.new)

    environment_name = env_name || (production ? "production" : "test")

    env_mock = Class.new do
      attr_reader :is_production, :environment_name

      def initialize(is_production, environment_name)
        @is_production = is_production
        @environment_name = environment_name
      end

      def production?
        @is_production
      end

      def to_s
        @environment_name
      end
    end.new(production, environment_name)

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

  def unstub_rails
    Object.send(:remove_const, :Rails) if defined?(Rails)
  end

  def create_test_backup_file
    backup_file = File.join(@test_dir, "test_backup.tar.gz")
    dump_content = "-- PostgreSQL database dump"

    # Create a simple tar.gz file with a dump inside
    dump_file = File.join(@test_dir, "test.pgsql")
    File.write(dump_file, dump_content)

    Dir.chdir(@test_dir) do
      system("tar -czf test_backup.tar.gz test.pgsql")
    end

    FileUtils.rm_f(dump_file)
    backup_file
  end
end

class Minitest::Test
  include TestHelpers
end
