# frozen_string_literal: true

require "zeitwerk"

loader = Zeitwerk::Loader.for_gem
loader.ignore("#{__dir__}/generators")
loader.setup

module Scalingo
  module StagingSync
    class Error < StandardError; end
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
  end
end

# Load Railtie if Rails is available
require "scalingo/staging_sync/railtie" if defined?(Rails)
