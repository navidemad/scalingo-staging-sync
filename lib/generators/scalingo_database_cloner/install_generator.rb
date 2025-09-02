# frozen_string_literal: true

require "rails/generators/base"

module ScalingoDatabaseCloner
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      desc "Create Scalingo Database Cloner initializer"

      def create_initializer_file
        template "scalingo_database_cloner.rb", "config/initializers/scalingo_database_cloner.rb"
      end

      def show_readme
        readme "README" if behavior == :invoke
      end
    end
  end
end
