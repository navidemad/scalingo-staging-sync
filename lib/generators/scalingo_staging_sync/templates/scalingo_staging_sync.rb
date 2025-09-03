# frozen_string_literal: true

# Configure the Scalingo Staging Sync
#
# This gem syncs and anonymizes Scalingo production databases for safe use in staging/demo environments.
#
# For more information, see: https://github.com/navidemad/scalingo-staging-sync

ScalingoStagingSync.configure do |config|
  # Required: Scalingo app to clone from (app name)
  config.clone_source_scalingo_app_name = "your-production-app"

  # Optional: Slack integration for notifications
  # config.slack_enabled = true
  # config.slack_channel = "#deployments"
  # config.slack_webhook_url = "https://hooks.slack.com/services/..."

  # Optional: Tables to exclude from cloning
  # config.exclude_tables = %w[
  #   temp_data
  #   audit_logs
  #   active_storage_blobs
  # ]

  # Optional: Number of parallel database connections for anonymization (default: 3)
  # config.parallel_connections = 3

  # Optional: Path to seeds file to run after cloning (no default - must be explicitly set)
  # config.seeds_file_path = Rails.root.join("db/seeds/staging.rb")

  # Optional: Whether to use PostGIS extension (default: false)
  # Set to true if your database uses PostGIS
  # config.postgis = true
end
