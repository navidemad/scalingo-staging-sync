# frozen_string_literal: true

require "rails/generators/base"

module ScalingoStagingSync
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      desc "Create Scalingo Staging Sync initializer"

      def create_initializer_file
        template "staging_sync.rb", "config/initializers/scalingo_staging_sync.rb"
      end

      def show_readme
        readme "README" if behavior == :invoke
      end
    end
  end
end
