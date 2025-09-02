# frozen_string_literal: true

require "zeitwerk"

loader = Zeitwerk::Loader.for_gem
loader.ignore("#{__dir__}/generators")
loader.setup

module Scalingo
  module Database
    module Cloner
      class Error < StandardError; end

      autoload :VERSION, "scalingo/database/cloner/version"
      autoload :Configuration, "scalingo/database/cloner/configuration"
      autoload :SlackWebhookClient, "scalingo/database/cloner/slack_webhook_client"
      autoload :DatabaseAnonymizerService, "scalingo/database/cloner/database_anonymizer_service"
      autoload :DatabaseBackupService, "scalingo/database/cloner/database_backup_service"
      autoload :DatabaseRestoreService, "scalingo/database/cloner/database_restore_service"
      autoload :SlackNotificationService, "scalingo/database/cloner/slack_notification_service"
      autoload :StagingSyncCoordinator, "scalingo/database/cloner/staging_sync_coordinator"
      autoload :StagingSyncTester, "scalingo/database/cloner/staging_sync_tester"
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
end

# Load Railtie if Rails is available
require "scalingo/database/clone/railtie" if defined?(Rails)
