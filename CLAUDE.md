# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Ruby gem called `scalingo-staging-sync` that handles cloning and anonymizing Scalingo production databases for safe use in staging/demo environments. The gem provides a comprehensive solution for safely syncing production data to staging environments with built-in anonymization and safety checks.

**Requirements:** PostgreSQL 16.x databases

### Project Resources
- **GitHub Repository**: https://github.com/navidemad/scalingo-staging-sync
- **RubyGems**: https://rubygems.org/gems/scalingo-staging-sync
- **Issue Tracker**: https://github.com/navidemad/scalingo-staging-sync/issues
- **License**: MIT

## Common Commands

### Development
- `bin/setup` - Initial project setup (installs dependencies and Overcommit hooks)
- `bin/console` - Start an interactive Ruby console with the gem loaded
- `bundle install` - Install dependencies
- `bundle exec rake` - Run default tasks (tests + linting)

### Testing
- `bundle exec rake test` - Run all tests with Minitest
- `bundle exec ruby -Ilib:test test/path/to/specific_test.rb` - Run a specific test file

### Linting and Code Quality
- `bundle exec rubocop` - Run RuboCop linter
- `bundle exec rubocop -a` - Auto-fix RuboCop violations where possible

### Build and Release
- `bundle exec rake build` - Build the gem (includes gemspec validation)
- `bundle exec rake release` - Release the gem (builds, tags, and pushes to RubyGems)
- `bundle exec rake bump` - Update Ruby version dependencies and year in license

### Database Cloning (when integrated in Rails app)
- `bundle exec rake scalingo_staging_sync:run` - Clone production database to current environment
- `bundle exec rake scalingo_staging_sync:check` - Test configuration and safety checks

## Architecture

### Module Structure
- `ScalingoStagingSync` - Main namespace module with Zeitwerk autoloading and configuration
- `ScalingoStagingSync::Configuration` - Configuration management using ActiveSupport::Configurable
- `ScalingoStagingSync::Services::Coordinator` - Main orchestrator for cloning process
- `ScalingoStagingSync::Services::DatabaseBackupService` - Handles Scalingo backup downloads
- `ScalingoStagingSync::Services::DatabaseRestoreService` - Database restoration with filtering
- `ScalingoStagingSync::Services::DatabaseAnonymizerService` - Parallel data anonymization
- `ScalingoStagingSync::Services::SlackNotificationService` - Status notifications to Slack

### Directory Structure
```
lib/
├── scalingo_staging_sync/
│   ├── configuration.rb        - Main configuration class
│   ├── railtie.rb              - Rails integration
│   ├── version.rb              - Version constant
│   ├── services/               - Core service classes
│   │   ├── coordinator.rb
│   │   ├── database_anonymizer_service.rb
│   │   ├── database_backup_service.rb
│   │   ├── database_restore_service.rb
│   │   └── slack_notification_service.rb
│   ├── database/               - Database-related utilities
│   │   ├── anonymization_queries.rb
│   │   ├── database_operations.rb
│   │   ├── restore_command_builder.rb
│   │   ├── table_anonymizer.rb
│   │   └── toc_filter.rb
│   ├── integrations/           - External service integrations
│   │   ├── scalingo_api_client.rb
│   │   ├── slack_message_formatter.rb
│   │   ├── slack_service_delegates.rb
│   │   └── slack_webhook_client.rb
│   ├── support/                - Helper modules and utilities
│   │   ├── archive_handler.rb
│   │   ├── coordinator_helpers.rb
│   │   ├── environment_validator.rb
│   │   ├── file_downloader.rb
│   │   ├── parallel_processor.rb
│   │   └── utilities.rb
│   └── testing/                - Testing utilities and validators
│       ├── config_tests.rb
│       ├── database_info_logger.rb
│       ├── environment_tests.rb
│       ├── system_tests.rb
│       └── tools_configuration.rb
├── generators/                  - Rails generators (excluded from autoloading)
│   └── scalingo_staging_sync/
│       ├── install_generator.rb
│       └── templates/
└── tasks/                       - Rake tasks
    └── scalingo_staging_sync.rake
```

### Key Files
- `lib/scalingo_staging_sync.rb` - Main entry point with Zeitwerk autoloading configuration
- `lib/scalingo_staging_sync/version.rb` - Version definition (not autoloaded)
- `lib/scalingo_staging_sync/railtie.rb` - Rails integration (lazy loaded)
- `lib/scalingo_staging_sync/configuration.rb` - Configuration with ActiveSupport::Configurable
- `test/test_helper.rb` - Test setup with TestHelpers module and mocking utilities

### Core Features
- **Database Cloning**: Downloads backups from Scalingo production environments
- **Data Anonymization**: Anonymizes sensitive data in parallel for performance
- **Safety Checks**: Prevents accidental production modifications and validates app names
- **Slack Integration**: Real-time progress updates via webhooks
- **Table Filtering**: Selective restoration excluding transient/sensitive tables

### Code Quality Tools
- **RuboCop**: Configured with multiple plugins (minitest, packaging, performance, rake)
- **Overcommit**: Git hooks for bundle check, RuboCop, FixMe detection, and YAML syntax
- **GitHub Actions**: CI pipeline testing Ruby 3.1-3.4 and head versions

## Development Notes

### Ruby Version Support
- Minimum Ruby version: 3.1
- CI tests on: 3.1, 3.2, 3.3, 3.4, head

### Runtime Dependencies
- `pg` - PostgreSQL adapter for database operations
- `rails` - Rails framework (required for Rails integration)
- `scalingo` - Scalingo API client for backup management
- `zeitwerk` - Code autoloading and reloading

### Development Dependencies
- `minitest` - Testing framework
- `minitest-rg` - Colored test output
- `rake` - Task automation
- `rubocop` with plugins: minitest, packaging, performance, rake

### Code Style
- Uses double quotes for strings (`EnforcedStyle: double_quotes`)
- Frozen string literals required in all Ruby files
- RuboCop configuration allows 18-line methods and 20 ABC complexity
- Line breaks enforced for multi-element arrays, hashes, and method arguments
- Indented style for multiline method calls
- No spaces around equals in parameter defaults

### Error Handling
- Base error class: `ScalingoStagingSync::Error`
- Scalingo-specific errors in `Integrations::ScalingoApiClient`:
  - `BackupError` - Base class for backup-related errors
  - `AddonNotFoundError` - Database addon not found
  - `BackupNotFoundError` - Backup not available
  - `DownloadError` - Backup download failed

### Autoloading with Zeitwerk
- All modules under `lib/scalingo_staging_sync/` are autoloaded
- Excluded from autoloading:
  - `lib/scalingo-staging-sync.rb` (main entry file)
  - `lib/generators/` (Rails generators)
  - `lib/scalingo_staging_sync/version.rb` (manually required)
- Lazy loaded: `lib/scalingo_staging_sync/railtie.rb` (only when Rails is defined)
- Reloading is enabled for development

### Testing
- Test helper module `TestHelpers` provides utilities:
  - Configuration reset before each test
  - Environment variable management with `with_env`
  - Temporary directory creation and cleanup
  - Mocking utilities for Scalingo client and Rails
  - Test backup file creation
- Tests use Minitest with mocking support
- Test files excluded from RuboCop complexity metrics

### Git Workflow
- Pre-commit hooks via Overcommit:
  - Bundle check
  - RuboCop linting (fails on warnings)
  - FixMe detection (FIXME comments)
  - YAML syntax validation
- CI runs on pull requests and pushes to main branch
- Dependabot configured for automated dependency updates
- Release process enhanced with GitHub release reminder

## Installation and Usage

### Installation in Rails Application
1. Add to Gemfile:
   ```ruby
   gem 'scalingo-staging-sync'
   ```

2. Run the generator:
   ```bash
   bundle exec rails generate scalingo_staging_sync:install
   ```
   This creates `config/initializers/scalingo_staging_sync.rb`

3. Configure the initializer (see Configuration section below)

4. Run database sync:
   ```bash
   bundle exec rake scalingo_staging_sync:run
   ```

### Bin Scripts
- `bin/console` - Interactive Ruby console with gem loaded (uses Pry if available)
- `bin/setup` - Initial setup (installs dependencies and Overcommit hooks)
- `bin/test` - Run tests (shortcut for `bundle exec rake test`)

## Configuration

When used in a Rails application, configure in initializer:

```ruby
# config/initializers/scalingo_staging_sync.rb
ScalingoStagingSync.configure do |config|
  config.clone_source_scalingo_app_name = "dummy-demo"        # Scalingo app to clone from
  # target_app automatically uses ENV["APP"] - not configurable
  config.slack_webhook_url = "https://hooks.slack.com/..."
  config.slack_channel = "#deployments"
  config.slack_enabled = true
  config.exclude_tables = [
    "temp_data",
    "audit_logs",
  ]
  config.parallel_connections = 4
  config.seeds_file_path = "db/demo_seeds.rb"               # Optional: seeds to run after sync
end
```

### Configuration Options
- `clone_source_scalingo_app_name`: Scalingo app to clone from (required)
- `target_app`: Always uses ENV["APP"] (NOT configurable - auto-detected on Scalingo)
- `slack_webhook_url`: Webhook for Slack notifications (optional)
- `slack_channel`: Slack channel for notifications (optional)
- `slack_enabled`: Enable/disable Slack notifications (default: false)
- `exclude_tables`: Tables to skip during cloning (default: [])
- `parallel_connections`: Number of parallel DB connections for anonymization (default: 3)
- `seeds_file_path`: Path to seeds file to run after cloning (optional)
- `logger`: Custom logger (defaults to Rails.logger)
- `temp_dir`: Directory for temporary files (defaults to Rails.root.join("tmp"))

### Required Environment Variables
- `APP` - Target Scalingo app name (automatically set on Scalingo)
- `SCALINGO_API_TOKEN` - API token for Scalingo authentication

## Important Implementation Details

### Service Organization
Services are organized under namespaces:
- `Services::` - Core business logic services
- `Database::` - Database-specific operations
- `Integrations::` - External service clients
- `Support::` - Helper modules and utilities
- `Testing::` - Test utilities and validators

### Module Inclusion Pattern
Services use module inclusion for shared functionality:
```ruby
class Coordinator
  include Support::EnvironmentValidator
  include Support::CoordinatorHelpers
end
```

### Logging
The gem uses Rails.logger with tagged logging for better traceability:
```ruby
@logger.tagged("SCALINGO_STAGING_SYNC") do
  # operations
end
```

### Safety Checks
- Environment validation prevents running in production
- App name validation ensures correct source/target
- Automatic rollback on errors during sync

## Scheduling with Cron

For automated database cloning on Scalingo, create a `cron.json` file at the root:

```json
{
  "jobs": [
    {
      "command": "0 7 * * 0 bundle exec rake scalingo_staging_sync:run",
      "size": "2XL"
    }
  ]
}
```

**Cron format**: `minute hour day-of-month month day-of-week`
**Common schedules**:
- `0 7 * * 0` - Every Sunday at 7:00 AM
- `0 2 * * 1` - Every Monday at 2:00 AM  
- `0 8 */3 * *` - Every 3 days at 8:00 AM

## Clone Workflow

The gem follows this process to safely clone and anonymize databases:

1. **Safety Checks** - Validate environment and configuration
2. **Initialize Services** - Set up coordinator and services
3. **Slack Notification** - Send "Starting Clone" message
4. **Find PostgreSQL Addon** - Locate database addon in Scalingo
5. **Request Backup** - Trigger backup creation from Scalingo API
6. **Poll Status** - Wait for backup to be ready
7. **Download Backup** - Retrieve backup archive
8. **Extract & Validate** - Unpack and verify backup files
9. **Drop Existing Database** - Clean current database
10. **Create Fresh Database** - Initialize new database
11. **Restore Database** - Use pg_restore or psql to restore
12. **Anonymize Data** - Run parallel anonymization queries
13. **Clean Temporary Files** - Remove downloaded backup files
14. **Slack Notification** - Send "Clone Complete" message

The entire process is coordinated by `Services::Coordinator` with error handling and rollback capabilities.