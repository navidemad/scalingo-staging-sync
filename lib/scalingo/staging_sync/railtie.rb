# frozen_string_literal: true

require "rails/railtie"

module Scalingo
  module StagingSync
    class Railtie < Rails::Railtie
      railtie_name "scalingo_staging_sync"

      generators do
        require "generators/staging_sync/install_generator"
      end

      rake_tasks do
        load "tasks/scalingo_staging_sync.rake"
      end
    end
  end
end