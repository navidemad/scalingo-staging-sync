# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Ruby gem called `scalingo-database-cloner` that handles cloning and anonymizing Scalingo production databases for safe use in staging/demo environments. The gem provides a comprehensive solution for safely syncing production data to staging environments with built-in anonymization and safety checks.

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
- `bundle exec rake scalingo_database:clone` - Clone production database to current environment
- `bundle exec rake scalingo_database:test_clone` - Test configuration and safety checks

## Architecture

### Module Structure
- `Scalingo::Database::Cloner` - Main namespace module with autoloading and configuration
- `Scalingo::Database::Cloner::Configuration` - Configuration management
- `Scalingo::Database::Cloner::StagingSyncCoordinator` - Main orchestrator for cloning process
- `Scalingo::Database::Cloner::DatabaseBackupService` - Handles Scalingo backup downloads
- `Scalingo::Database::Cloner::DatabaseRestoreService` - Database restoration with filtering
- `Scalingo::Database::Cloner::DatabaseAnonymizerService` - Parallel data anonymization
- `Scalingo::Database::Cloner::SlackNotificationService` - Status notifications to Slack
- `Scalingo::Database::Cloner::SlackWebhookClient` - Internal HTTP client for Slack
- `Scalingo::Database::Cloner::StagingSyncTester` - Configuration and safety testing
- `Scalingo::Database::Cloner::VERSION` - Version constant

### Key Files
- `lib/scalingo/database/cloner.rb` - Main entry point with autoload and configuration setup
- `lib/scalingo/database/cloner/version.rb` - Version definition
- `test/scalingo/database/cloner_test.rb` - Basic test ensuring version exists

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

### Code Style
- Uses double quotes for strings (`EnforcedStyle: double_quotes`)
- Frozen string literals required in all Ruby files
- RuboCop configuration allows 18-line methods and 20 ABC complexity

### Git Workflow
- Pre-commit hooks run automatically via Overcommit
- CI runs on pull requests and pushes to main branch
- Dependabot configured for automated dependency updates

## Configuration

When used in a Rails application, configure in initializer:

```ruby
# config/initializers/scalingo_database_cloner.rb
ScalingoDatabaseCloner.configure do |config|
  config.clone_source_scalingo_app_name = "dummy-demo"        # Scalingo app to clone from
  # target_app automatically uses ENV["APP"] - not configurable
  config.slack_channel = "#deployments"
  config.slack_enabled = true
  config.exclude_tables = ["temp_data", "audit_logs"]
  config.parallel_connections = 4
end
```

### Configuration Options
- `clone_source_scalingo_app_name`: Scalingo app to clone from
- `target_app`: Always uses ENV["APP"] (not configurable)
- `slack_webhook_url`: Webhook for Slack notifications
- `slack_channel`: Slack channel for notifications
- `slack_enabled`: Enable/disable Slack notifications
- `exclude_tables`: Tables to skip during cloning
- `parallel_connections`: Number of parallel DB connections for anonymization
- `seeds_file_path`: Path to seeds file to run after cloning