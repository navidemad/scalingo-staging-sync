# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "scalingo_staging_sync"

require "minitest/autorun"
require "minitest/mock"
require "logger"
require "tmpdir"
require "fileutils"

# Load support files
Dir[File.expand_path("support/**/*.rb", __dir__)].each { |rb| require(rb) }

# Test helper module for common test utilities
module TestHelpers
  def setup
    super
    # Reset configuration before each test
    ScalingoStagingSync.reset_configuration!

    # Set up test environment variables
    @original_env = {}
    @test_dir = Dir.mktmpdir("scalingo_staging_sync_test")
    @logger = Logger.new(StringIO.new)
  end

  def teardown
    super
    # Clean up test directory
    FileUtils.rm_rf(@test_dir) if @test_dir && File.exist?(@test_dir)

    # Restore original environment variables
    @original_env.each do |key, value|
      if value.nil?
        ENV.delete(key)
      else
        ENV[key] = value
      end
    end
  end

  def with_env(env_vars)
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
    rails = Object.const_set(:Rails, Module.new) unless defined?(Rails)

    env = Minitest::Mock.new
    env.expect(:production?, false)
    env.expect(:to_s, "test")

    root = Minitest::Mock.new
    root.expect(:join, Pathname.new(@test_dir), ["tmp"])

    rails.define_singleton_method(:env) { env }
    rails.define_singleton_method(:root) { root }
    rails.define_singleton_method(:logger) { @logger }

    rails
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
