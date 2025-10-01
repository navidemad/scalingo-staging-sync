# frozen_string_literal: true

require "scalingo"

module ScalingoStagingSync
  module Integrations
    # Handles Scalingo API interactions for backup operations
    class ScalingoApiClient
      def initialize(source_app, logger: Rails.logger)
        @source_app = source_app
        @logger = logger
        @client = initialize_client
      end

      def postgresql_addon_id
        addons = @client.osc_fr1.addons.for(@source_app)
        pg_addon = addons.data.find { |addon| addon[:addon_provider][:id] == "postgresql" }

        raise BackupService::AddonNotFoundError, "No PostgreSQL addon found for app #{@source_app}" unless pg_addon

        @logger.info "[ScalingoApiClient] Found PostgreSQL addon: #{pg_addon[:id]}"
        pg_addon[:id]
      end

      def database_client(addon_id)
        response = @client.osc_fr1.addons.token(@source_app, addon_id)
        bearer_token = response.data&.dig(:token)

        raise BackupService::BackupError, "Failed to authenticate with addon" unless bearer_token

        database_api_url = "https://db-api.osc-fr1.scalingo.com/api/databases/#{addon_id}"
        addon_config = Scalingo::Client.new
        addon_config.token = bearer_token

        Scalingo::API::Client.new(database_api_url, scalingo: addon_config)
      end

      def latest_backup(db_client, addon_id)
        database_api_url = "https://db-api.osc-fr1.scalingo.com/api/databases/#{addon_id}"
        response = db_client.authenticated_connection.get("#{database_api_url}/backups").body

        backups = response[:database_backups] || []
        raise BackupService::BackupNotFoundError, "No backups found for addon #{addon_id}" if backups.empty?

        latest = backups.max_by { |b| Time.zone.parse(b[:created_at]) }
        @logger.info "[ScalingoApiClient] Found latest backup: #{latest[:id]} (created: #{latest[:created_at]})"
        latest
      end

      def backup_download_url(db_client, addon_id, backup_id)
        database_api_url = "https://db-api.osc-fr1.scalingo.com/api/databases/#{addon_id}"
        archive_url = "#{database_api_url}/backups/#{backup_id}/archive"

        archive_response = db_client.authenticated_connection.get(archive_url).body
        download_url = archive_response[:download_url]

        raise BackupService::DownloadError, "No download URL received" unless download_url

        download_url
      end

      private

      def initialize_client
        token = ENV.fetch("SCALINGO_API_TOKEN") do
          raise BackupService::BackupError, "SCALINGO_API_TOKEN environment variable not set"
        end

        client = Scalingo::Client.new
        client.authenticate_with(access_token: token)
        @logger.info "[ScalingoApiClient] Authenticated successfully"
        client
      rescue StandardError => e
        @logger.error "[ScalingoApiClient] Failed to initialize: #{e.message}"
        raise
      end
    end

    # Module for backward compatibility with BackupService error classes
    module BackupService
      class BackupError < StandardError; end
      class AddonNotFoundError < BackupError; end
      class BackupNotFoundError < BackupError; end
      class DownloadError < BackupError; end
    end
  end
end
