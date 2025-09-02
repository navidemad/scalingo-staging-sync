# frozen_string_literal: true

require "zeitwerk"

lib_dir = File.join(File.dirname(__dir__), "lib")
lib_scalingo_staging_sync_dir = File.join(File.dirname(__dir__), "lib", "scalingo_staging_sync")

gem_loader = Zeitwerk::Loader.for_gem
gem_loader.ignore("#{lib_dir}/scalingo-staging-sync.rb")
gem_loader.ignore "#{lib_dir}/generators"
gem_loader.ignore("#{lib_scalingo_staging_sync_dir}/version.rb")
gem_loader.do_not_eager_load("#{lib_scalingo_staging_sync_dir}/railtie.rb")
gem_loader.enable_reloading
gem_loader.setup

require_relative "scalingo_staging_sync/version"

module ScalingoStagingSync
  class << self
    attr_writer :configuration

    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end

    def reset_configuration!
      @configuration = Configuration.new
    end
  end

  class Error < StandardError; end
end

require "scalingo_staging_sync/railtie" if defined?(Rails)
gem_loader.eager_load
