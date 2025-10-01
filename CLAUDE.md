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
│   ├── configuration.rb        - Main configuration class (25+ options)
│   ├── railtie.rb              - Rails integration
│   ├── version.rb              - Version constant
│   ├── services/               - Core service classes
│   │   ├── coordinator.rb
│   │   ├── database_anonymizer_service.rb
│   │   ├── database_backup_service.rb
│   │   ├── database_restore_service.rb
│   │   └── slack_notification_service.rb
│   ├── database/               - Database-related utilities
│   │   ├── anonymization_audit.rb          (NEW) - Audit trail generation
│   │   ├── anonymization_queries.rb        - SQL queries for anonymization
│   │   ├── anonymization_strategies.rb     (NEW) - Built-in strategies system
│   │   ├── anonymization_verifier.rb       (NEW) - Post-anonymization verification
│   │   ├── column_validator.rb             (NEW) - Pre-anonymization column checks
│   │   ├── database_operations.rb          - Database drop/create/migrate
│   │   ├── pii_scanner.rb                  (NEW) - PII detection scanner
│   │   ├── restore_command_builder.rb      - pg_restore command builder
│   │   ├── table_anonymizer.rb             - Individual table anonymization
│   │   ├── toc_filter.rb                   - TOC filtering for pg_restore
│   │   └── transaction_helpers.rb          (NEW) - Transaction management
│   ├── integrations/           - External service integrations
│   │   ├── scalingo_api_client.rb
│   │   ├── slack_message_formatter.rb
│   │   ├── slack_service_delegates.rb
│   │   └── slack_webhook_client.rb
│   ├── support/                - Helper modules and utilities
│   │   ├── archive_handler.rb
│   │   ├── coordinator_helpers.rb
│   │   ├── environment_validator.rb        (ENHANCED) - Multi-factor protection
│   │   ├── file_downloader.rb
│   │   ├── parallel_processor.rb           (ENHANCED) - Thread coordination
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

test/
├── test_helper.rb              - Test setup with PG mocking
└── scalingo_staging_sync/
    ├── database/
    │   ├── anonymization_verifier_test.rb  (NEW)
    │   ├── column_validator_test.rb        (NEW)
    │   └── database_operations_test.rb     (NEW)
    ├── integrations/
    │   └── scalingo_api_client_test.rb     (NEW)
    ├── services/
    │   ├── coordinator_test.rb             (NEW)
    │   ├── database_anonymizer_service_test.rb (NEW)
    │   ├── database_backup_service_test.rb (NEW)
    │   └── database_restore_service_test.rb (NEW)
    └── support/
        ├── environment_validator_test.rb   (NEW)
        └── utilities_test.rb               (NEW)
```

### Key Files
- `lib/scalingo_staging_sync.rb` - Main entry point with Zeitwerk autoloading configuration
- `lib/scalingo_staging_sync/version.rb` - Version definition (not autoloaded)
- `lib/scalingo_staging_sync/railtie.rb` - Rails integration (lazy loaded)
- `lib/scalingo_staging_sync/configuration.rb` - Configuration with ActiveSupport::Configurable
- `test/test_helper.rb` - Test setup with TestHelpers module and mocking utilities

### Core Features

#### Security Features
- **Multi-Factor Production Protection**: Rails.env check, APP name validation, DATABASE_URL hostname validation
- **Interactive Confirmation Mode**: Requires typing app name to confirm (skipped in CI)
- **Dry-Run Mode**: Test configuration without executing operations
- **Command Injection Protection**: All shell commands use Open3 with argument arrays
- **Transaction Wrapping**: Savepoint-based transactions with automatic rollback on error

#### Anonymization Features
- **Configurable Anonymization**: Define tables and strategies in configuration
- **Built-in Strategies**: 5 pre-built strategies (user, phone, payment, email, address)
- **Custom Strategies**: Register custom anonymization strategies via registry
- **Custom SQL Queries**: Support for inline SQL anonymization
- **Parallel Processing**: Multi-threaded anonymization with configurable connections
- **Verification System**: Pre and post-anonymization checks
- **PII Detection Scanner**: Automatically scan for unanonymized sensitive columns
- **Audit Trails**: Generate JSON and text audit reports with before/after state
- **Retry Logic**: Exponential backoff retry for transient failures

#### Database Operations
- **Database Cloning**: Downloads backups from Scalingo production environments
- **Table Filtering**: Selective restoration excluding transient/sensitive tables
- **pg_restore Support**: Parallel restore with custom TOC filtering
- **PostGIS Support**: Special handling for PostGIS databases
- **Slack Integration**: Real-time progress updates via webhooks

### Code Quality Tools
- **RuboCop**: Configured with multiple plugins (minitest, packaging, performance, rake)
- **Overcommit**: Git hooks for bundle check, RuboCop, FixMe detection, and YAML syntax
- **GitHub Actions**: CI pipeline testing Ruby 3.4 and head versions

## Development Notes

### Ruby Version Support
- Minimum Ruby version: 3.4
- CI tests on: 3.4, head

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
- **Test Coverage**: 8 test files with 3,135+ lines covering:
  - Safety validators (67 test scenarios)
  - Core services (74 test scenarios)
  - Database operations (13 test scenarios)
  - Support utilities (15 test scenarios)
  - API integrations (11 test scenarios)
- Test helper module `TestHelpers` provides utilities:
  - Configuration reset before each test
  - Environment variable management with `with_env`
  - Temporary directory creation and cleanup
  - Mocking utilities for Scalingo client, Rails, and PG
  - Test backup file creation
- Tests use Minitest with mocking support
- Test files excluded from RuboCop complexity metrics
- CI runs tests on Ruby 3.4 and head versions

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
  # === REQUIRED ===
  config.clone_source_scalingo_app_name = "my-production-app"  # Scalingo app to clone from
  # target_app automatically uses ENV["APP"] - not configurable

  # === SECURITY SETTINGS ===
  config.production_hostname_patterns = [/prod/i, /production/i]        # Hostname patterns to block
  config.production_app_name_patterns = [/prod/i, /production/i]        # APP name patterns to block
  config.require_confirmation = false                                    # Require typing app name to confirm
  config.dry_run = false                                                 # Test mode without execution

  # === ANONYMIZATION CONFIGURATION ===
  config.anonymization_tables = [
    { table: "users", strategy: :user_anonymization, translation: "utilisateurs" },
    { table: "phone_numbers", strategy: :phone_anonymization, translation: "téléphones" },
    { table: "payment_methods", strategy: :payment_anonymization, translation: "moyens de paiement" },
    { table: "custom_table", query: "UPDATE custom_table SET sensitive = NULL" }
  ]

  # === TRANSACTION & RETRY SETTINGS ===
  config.anonymization_rollback_on_error = true     # Roll back all changes on any error
  config.anonymization_retry_attempts = 3           # Number of retry attempts
  config.anonymization_retry_delay = 1.0            # Base delay for exponential backoff (seconds)

  # === VERIFICATION SETTINGS ===
  config.verify_anonymization = true                # Verify anonymization succeeded
  config.fail_on_verification_error = true          # Fail if verification finds issues
  config.pii_detection_patterns = nil               # Custom PII detection patterns (nil = use defaults)
  config.anonymization_audit_file = "tmp/anonymization_audit"  # Path for audit reports
  config.run_pii_scan = true                        # Scan for unanonymized PII columns

  # === PERFORMANCE SETTINGS ===
  config.parallel_connections = 4                   # Number of parallel DB connections
  config.exclude_tables = ["temp_data", "audit_logs"]  # Tables to skip during restore

  # === OTHER SETTINGS ===
  config.slack_webhook_url = "https://hooks.slack.com/..."
  config.slack_channel = "#deployments"
  config.slack_enabled = true
  config.seeds_file_path = "db/demo_seeds.rb"      # Optional: seeds to run after sync
  config.postgis = false                            # Set to true for PostGIS databases
  config.logger = Rails.logger                      # Custom logger
  config.temp_dir = Rails.root.join("tmp")          # Temporary files directory
end
```

### Configuration Options (25+ options)

#### Required
- `clone_source_scalingo_app_name`: Scalingo app to clone from (String, required)
- `target_app`: Always uses ENV["APP"] (NOT configurable - auto-detected on Scalingo)

#### Security Settings
- `production_hostname_patterns`: Array of regex patterns to block (default: [/prod/i, /production/i])
- `production_app_name_patterns`: Array of regex patterns to block (default: [/prod/i, /production/i])
- `require_confirmation`: Require typing app name to confirm (default: false, skipped in CI)
- `dry_run`: Test mode without execution (default: false)

#### Anonymization Configuration
- `anonymization_tables`: Array of hashes defining tables and strategies (default: [], see example above)
  - Each hash can have: `table`, `strategy`, `query`, `condition`, `translation`

#### Transaction & Retry Settings
- `anonymization_rollback_on_error`: Roll back all changes on error (default: true)
- `anonymization_retry_attempts`: Number of retry attempts (default: 3)
- `anonymization_retry_delay`: Base delay for exponential backoff in seconds (default: 1.0)

#### Verification Settings
- `verify_anonymization`: Verify anonymization succeeded (default: true)
- `fail_on_verification_error`: Fail if verification finds issues (default: true)
- `pii_detection_patterns`: Custom PII detection patterns (default: nil = use built-in)
- `anonymization_audit_file`: Path for audit reports (default: nil = no audit)
- `run_pii_scan`: Scan for unanonymized PII columns (default: true)

#### Performance Settings
- `parallel_connections`: Number of parallel DB connections (default: 3)
- `exclude_tables`: Tables to skip during restore (default: [])

#### Slack Notifications
- `slack_webhook_url`: Webhook for Slack notifications (optional)
- `slack_channel`: Slack channel for notifications (optional)
- `slack_enabled`: Enable/disable Slack notifications (default: false)

#### Other Settings
- `seeds_file_path`: Path to seeds file to run after cloning (optional)
- `logger`: Custom logger (defaults to Rails.logger)
- `temp_dir`: Directory for temporary files (defaults to Rails.root.join("tmp"))
- `postgis`: Whether to use PostGIS extension (default: false)

### Required Environment Variables
- `APP` - Target Scalingo app name (automatically set on Scalingo)
- `SCALINGO_API_TOKEN` - API token for Scalingo authentication

## Built-in Anonymization Strategies

The gem provides 5 built-in strategies that can be used in the `anonymization_tables` configuration:

### 1. `:user_anonymization`
Comprehensive user data anonymization:
- **Email**: Hashed email with @demo.yespark.fr domain
- **Names**: First name → "Demo", Last name → "User{id}"
- **Payment Info**: credit_card_last_4, iban_last4 → "0000", stripe_customer_id → NULL
- **Address**: Generic Paris address (8 rue du sentier, 75002)
- **Tokens**: google_token, facebook_token, apple_id → NULL
- **Personal**: birth_date, birth_place, billing_extra, zendesk_user_id → NULL

### 2. `:phone_anonymization`
Phone number anonymization:
- Generates consistent fake French phone numbers: `060{padded_user_id_or_id}`
- Example: user_id=123 → `0600000123`

### 3. `:payment_anonymization`
Payment method anonymization:
- Sets `card_last4` to "0000"

### 4. `:email_anonymization`
Email-only anonymization (lighter than full user):
- Generates hashed email: `{hash}@demo.example.com`

### 5. `:address_anonymization`
Address field anonymization:
- Sets generic demo addresses without touching other fields

### Custom Strategies

You can register custom strategies:

```ruby
# In your Rails initializer, after the configuration:
ScalingoStagingSync::Database::AnonymizationStrategies.register_strategy(:gdpr_anonymization) do |table, condition|
  <<~SQL.squish
    UPDATE #{table}
    SET personal_data = NULL, gdpr_consent = false, anonymized_at = NOW()
    WHERE gdpr_consent = true
  SQL
end

# Then use it in configuration:
config.anonymization_tables = [
  { table: "customers", strategy: :gdpr_anonymization }
]
```

### Custom SQL Queries

For one-off anonymization, use inline SQL:

```ruby
config.anonymization_tables = [
  { table: "api_keys", query: "UPDATE api_keys SET key = MD5(RANDOM()::text)" },
  { table: "sessions", query: "DELETE FROM sessions WHERE updated_at < NOW() - INTERVAL '1 day'" }
]
```

### Conditional Anonymization

Add WHERE clause conditions:

```ruby
config.anonymization_tables = [
  {
    table: "old_accounts",
    strategy: :user_anonymization,
    condition: "created_at < NOW() - INTERVAL '1 year'"
  }
]
```

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

The gem implements multiple layers of production protection:

1. **Rails Environment Check**: Blocks if `Rails.env.production?` returns true
2. **APP Name Pattern Matching**: Checks against configurable regex patterns (default: /prod/i, /production/i)
3. **DATABASE_URL Hostname Validation**: Parses and checks hostname against production patterns
4. **SCALINGO_POSTGRESQL_URL Hostname Validation**: Separately validates Scalingo database URL
5. **Interactive Confirmation** (optional): Requires typing exact app name to proceed (skipped in CI)
6. **Dry-Run Mode**: Test configuration without executing operations
7. **Transaction Wrapping**: All anonymization operations wrapped in transactions with automatic rollback
8. **Verification Checks**: Pre and post-anonymization validation to ensure PII is actually anonymized
9. **Command Injection Protection**: All shell commands use Open3 with argument arrays
10. **Thread Coordination**: Parallel operations stop gracefully on first error

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

### Phase 1: Safety Validation
1. **Multi-Factor Safety Checks** - Validate Rails.env, APP name, DATABASE_URL hostname
2. **Interactive Confirmation** (if enabled) - Require user to type app name
3. **Dry-Run Check** - If enabled, simulate without executing

### Phase 2: Backup Download
4. **Initialize Services** - Set up coordinator and services
5. **Slack Notification** - Send "Starting Clone" message
6. **Find PostgreSQL Addon** - Locate database addon in Scalingo
7. **Request Backup** - Trigger backup creation from Scalingo API (or use cached)
8. **Poll Status** - Wait for backup to be ready
9. **Download Backup** - Retrieve backup archive with progress tracking
10. **Extract & Validate** - Unpack and verify backup files

### Phase 3: Database Restoration
11. **Drop Existing Database** - Clean current database with safety checks
12. **Create Fresh Database** - Initialize new database
13. **Generate Filtered TOC** (if exclude_tables) - Create custom restore list
14. **Restore Database** - Use pg_restore (parallel) or psql to restore
15. **Run Migrations** - Apply any pending migrations

### Phase 4: Data Anonymization
16. **Pre-Anonymization Validation** - Check required columns exist
17. **PII Scan** - Detect unanonymized sensitive columns
18. **Parallel Anonymization** - Run anonymization in parallel threads with:
    - Savepoint transactions per table
    - Retry logic with exponential backoff
    - Verification after each table
    - Thread coordination (stop all on first error)
19. **Post-Anonymization Verification** - Verify no PII remains
20. **Generate Audit Report** - Create JSON and text audit trails

### Phase 5: Finalization
21. **Run Staging Seeds** (if configured) - Execute demo data seeds
22. **Clean Temporary Files** - Remove downloaded backup files
23. **Slack Notification** - Send "Clone Complete" message with duration

### Error Handling
- **Transaction Rollback**: If `anonymization_rollback_on_error` is enabled, all anonymization changes are rolled back on error
- **Thread Coordination**: All parallel threads stop gracefully on first error
- **Cleanup**: Temporary files are cleaned up even on error
- **Detailed Logging**: All operations logged with context for debugging

The entire process is coordinated by `Services::Coordinator` with comprehensive error handling and rollback capabilities.