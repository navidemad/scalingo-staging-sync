# frozen_string_literal: true

require "rails/railtie"

module Scalingo
  module Database
    module Cloner
      class Railtie < Rails::Railtie
        railtie_name "scalingo_database_cloner"

        generators do
          require "generators/scalingo_database_cloner/install_generator"
        end

        rake_tasks do
          load "tasks/scalingo_database_cloner.rake"
        end
      end
    end
  end
end
