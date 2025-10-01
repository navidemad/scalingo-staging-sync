# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2025-09-30

### 🎉 Initial Release

This is the first public release of scalingo-staging-sync, a comprehensive solution for safely cloning and anonymizing Scalingo production databases for staging environments.

### ✨ Added - Security Features

#### Multi-Factor Production Environment Protection
- **Rails Environment Check**: Automatically blocks operations in `Rails.env.production?`
- **APP Name Pattern Validation**: Configurable regex patterns to detect production app names
  - Default patterns: `/prod/i`, `/production/i`
  - Configuration: `production_app_name_patterns`
- **Database Hostname Validation**: Configurable regex patterns to detect production database hostnames
  - Default patterns: `/prod/i`, `/production/i`
  - Configuration: `production_hostname_patterns`
  - Validates both `DATABASE_URL` and `SCALINGO_POSTGRESQL_URL`
- **Comprehensive Error Reporting**: Detailed remediation steps when safety checks fail

#### Interactive Confirmation Mode
- **User Confirmation**: Optional interactive prompt requiring exact target app name
  - Configuration: `require_confirmation` (default: `false`)
  - Automatically skipped in CI environments (`CI=true` or `CONTINUOUS_INTEGRATION=true`)
  - Prevents accidental runs in sensitive environments

#### Dry-Run Mode
- **Simulation Mode**: Test configuration without making actual changes
  - Configuration: `dry_run` (default: `false`)
  - Environment variable support: `DRY_RUN=true`
  - Logs all operations without executing them
  - Perfect for testing new anonymization strategies

#### Command Injection Protection
- **SQL Identifier Sanitization**: All SQL identifiers are properly escaped
- **Parameterized Queries**: Uses PostgreSQL parameterized queries where applicable
- **Savepoint Name Sanitization**: Transaction savepoints are sanitized (alphanumeric + underscore only)

### ✨ Added - Anonymization Features

#### Configurable Anonymization Tables
- **Strategy-Based Configuration**: Define anonymization tables with reusable strategies
  ```ruby
  config.anonymization_tables = [
    { table: 'users', strategy: :user_anonymization, translation: 'utilisateurs' },
    { table: 'phone_numbers', strategy: :phone_anonymization },
    { table: 'custom', query: 'UPDATE custom SET field = NULL' }
  ]
  ```
- **Conditional Anonymization**: Apply WHERE clauses to anonymize specific rows
  ```ruby
  { table: 'users', strategy: :user_anonymization, condition: "anonymized_at IS NULL" }
  ```
- **French Translation Support**: Optional `translation` key for Slack notifications

#### Built-in Anonymization Strategies
Five pre-built strategies for common data types:

1. **`:user_anonymization`**
   - Email addresses (SHA256 hashed + domain)
   - Names (replaced with "Demo User" + ID)
   - Credit card and IBAN last 4 digits
   - Social auth tokens (Stripe, Google, Facebook, Apple)
   - Birth dates and addresses

2. **`:phone_anonymization`**
   - Generates consistent fake phone numbers: `060` + 7-digit padded ID
   - Example: `0600000123` for user ID 123

3. **`:payment_anonymization`**
   - Card last 4 digits set to `0000`

4. **`:email_anonymization`**
   - Simple email-only anonymization
   - SHA256 hash + `@demo.example.com`

5. **`:address_anonymization`**
   - Generic address replacement
   - Street: `123 Demo Street`, City: `Demo City`, Postal: `00000`

#### Custom Anonymization Strategies
- **Strategy Registration System**: Register reusable anonymization patterns
  ```ruby
  ScalingoStagingSync::Database::AnonymizationStrategies.register_strategy(:custom) do |table, condition|
    query = "UPDATE #{table} SET field = 'value'"
    query += " WHERE #{condition}" if condition
    query
  end
  ```
- **Strategy Validation**: Validates strategy existence at configuration time
- **Error Messages**: Clear error messages listing available strategies

#### Custom SQL Query Support
- **Inline SQL Queries**: Define table-specific anonymization with raw SQL
  ```ruby
  { table: 'api_keys', query: 'UPDATE api_keys SET key = NULL' }
  ```
- **Complex Transformations**: Support for multi-line SQL with `<<~SQL.squish`
- **Query + Condition**: Combine custom queries with WHERE clauses

#### Transaction Wrapping with Rollback
- **Automatic Transactions**: Each table anonymization wrapped in transaction
- **Savepoint Support**: Uses PostgreSQL savepoints for nested transaction safety
- **Rollback on Error**: Automatically rolls back failed anonymizations
  - Configuration: `anonymization_rollback_on_error` (default: `true`)
- **Transaction Logging**: Detailed logging of BEGIN/COMMIT/ROLLBACK operations

#### Retry Logic with Exponential Backoff
- **Automatic Retries**: Failed operations are retried automatically
  - Configuration: `anonymization_retry_attempts` (default: `3`)
  - Configuration: `anonymization_retry_delay` (default: `1.0` seconds)
- **Exponential Backoff**: Delay doubles with each retry (1s, 2s, 4s)
- **Retry Logging**: Clear logging of retry attempts and delays

#### Verification and Audit Trails
- **Post-Anonymization Verification**: Verifies anonymization succeeded
  - Configuration: `verify_anonymization` (default: `true`)
  - Configuration: `fail_on_verification_error` (default: `true`)
- **Column Validation**: Pre-checks that required columns exist before anonymization
- **Row Count Verification**: Confirms expected number of rows were affected
- **Detailed Verification Results**: Per-table verification status tracking

#### PII Detection Scanner
- **Automatic PII Detection**: Scans for potential PII columns across all tables
  - Configuration: `run_pii_scan` (default: `true`)
- **Configurable Patterns**: Customize PII detection patterns
  ```ruby
  config.pii_detection_patterns = {
    identity: /\b(ssn|passport|tax_id)\b/i,
    contact: /\b(email|phone|address)\b/i,
    financial: /\b(credit_card|iban|account)\b/i,
    medical: /\b(diagnosis|prescription)\b/i,
    biometric: /\b(fingerprint|retina|dna)\b/i
  }
  ```
- **Default Patterns**: Comprehensive built-in PII patterns for common field types
- **High Cardinality Detection**: Identifies varchar columns with >80% unique values
- **Scan Reports**: Generates detailed reports of unanonymized PII columns
- **Slack Integration**: Reports PII scan results to Slack

#### Audit Report Generation
- **Detailed Audit Reports**: Optional JSON and text audit files
  - Configuration: `anonymization_audit_file` (e.g., `"tmp/anonymization_audit.json"`)
- **Dual Format Output**: Generates both `.json` (machine-readable) and `.txt` (human-readable)
- **Audit Contents**:
  - Pre- and post-anonymization state for each table
  - Row counts affected per table
  - Verification results with issues and warnings
  - PII scan results before and after anonymization
  - Timestamps and duration of all operations
- **Slack Notification**: Confirms audit report generation

### ✨ Added - Core Features

#### Database Cloning
- **Scalingo API Integration**: Automated backup creation and download
- **Streaming Downloads**: Efficient download of large backup archives
- **Archive Extraction**: Automatic tar.gz extraction with validation
- **Table Filtering**: Selective restoration excluding configured tables
  - Configuration: `exclude_tables` (default: `[]`)

#### Database Restoration
- **PostgreSQL Support**: PostgreSQL 14.x, 15.x, 16.x
- **PostGIS Support**: Optional PostGIS extension support
  - Configuration: `postgis` (default: `false`)
- **Smart Restore**: Handles both pg_dump and SQL formats
- **Connection Pooling**: Efficient parallel connections for large databases

#### Parallel Processing
- **Configurable Parallelism**: Distribute anonymization across multiple connections
  - Configuration: `parallel_connections` (default: `3`)
- **Work Queue Distribution**: Even distribution of tables across connections
- **Thread Safety**: Thread-safe connection management
- **Performance Logging**: Per-connection work queue logging

#### Slack Integration
- **Real-time Notifications**: Progress updates sent to Slack
  - Configuration: `slack_enabled` (default: `false`)
  - Configuration: `slack_webhook_url`
  - Configuration: `slack_channel`
- **French Language Support**: All notifications in French
- **Step-by-Step Updates**: Notifications for each major operation
- **Error Notifications**: Immediate alerts on failures
- **Formatted Messages**: Rich formatting with emojis and sections

#### Post-Clone Seeds
- **Optional Seed Execution**: Run seed files after cloning
  - Configuration: `seeds_file_path` (optional)
- **Demo Data Support**: Perfect for adding demo-specific data
- **Error Handling**: Continues even if seeds fail

### 📚 Added - Documentation

#### Comprehensive README
- Quick start guide (2 minutes to first clone)
- Detailed configuration examples
- Built-in strategy documentation
- Custom strategy registration guide
- Security best practices
- Real-world examples (e-commerce, SaaS, healthcare, finance)
- Performance benchmarks and optimization tips
- Troubleshooting guide
- FAQ section

#### Code Documentation
- Inline documentation for all modules
- YARD-compatible method documentation
- Module purpose descriptions
- Configuration option descriptions with defaults

### 🏗️ Added - Architecture

#### Module Organization
- `Services::` - Core business logic
  - `Coordinator` - Main orchestrator
  - `DatabaseBackupService` - Scalingo API integration
  - `DatabaseRestoreService` - Database restoration
  - `DatabaseAnonymizerService` - Data anonymization
  - `SlackNotificationService` - Slack integration
- `Database::` - Database operations
  - `AnonymizationStrategies` - Strategy registry
  - `AnonymizationQueries` - Legacy query methods
  - `TransactionHelpers` - Transaction management
  - `ColumnValidator` - Column existence validation
  - `AnonymizationVerifier` - Post-anonymization verification
  - `PiiScanner` - PII detection
  - `AnonymizationAudit` - Audit report generation
- `Support::` - Helper modules
  - `EnvironmentValidator` - Multi-factor safety checks
  - `ParallelProcessor` - Thread management
  - `ArchiveHandler` - Backup extraction
  - `FileDownloader` - HTTP downloads
- `Integrations::` - External services
  - `ScalingoApiClient` - Scalingo API wrapper
  - `SlackWebhookClient` - Slack webhook handling

#### Error Handling
- Custom error classes
- Detailed error messages with remediation steps
- Automatic cleanup on errors
- Graceful degradation

### 🧪 Added - Testing

#### Test Suite
- Comprehensive test coverage
- Minitest framework
- Mock-based testing for external services
- Test helpers for common scenarios

### 🔧 Added - Development Tools

#### Code Quality
- RuboCop linting with multiple plugins
- Overcommit git hooks
- GitHub Actions CI
- Dependabot updates

#### Development Scripts
- `bin/setup` - Project setup
- `bin/console` - Interactive console
- `bin/test` - Test runner

### 📝 Configuration Reference

#### New Configuration Options

**Security Settings:**
- `production_hostname_patterns` - Array of regex patterns for production hostnames (default: `[/prod/i, /production/i]`)
- `production_app_name_patterns` - Array of regex patterns for production app names (default: `[/prod/i, /production/i]`)
- `require_confirmation` - Boolean to enable interactive confirmation (default: `false`)
- `dry_run` - Boolean to enable simulation mode (default: `false`)

**Anonymization Settings:**
- `anonymization_tables` - Array of table configurations with strategies/queries (default: `[]`)
- `anonymization_rollback_on_error` - Boolean to enable rollback on errors (default: `true`)
- `anonymization_retry_attempts` - Integer number of retry attempts (default: `3`)
- `anonymization_retry_delay` - Float delay in seconds between retries (default: `1.0`)

**Verification Settings:**
- `verify_anonymization` - Boolean to enable verification (default: `true`)
- `fail_on_verification_error` - Boolean to fail on verification errors (default: `true`)
- `pii_detection_patterns` - Hash of PII patterns for detection (default: built-in patterns)
- `anonymization_audit_file` - String path for audit report file (default: `nil`)
- `run_pii_scan` - Boolean to enable PII scanning (default: `true`)

**Existing Settings:**
- `clone_source_scalingo_app_name` - Source Scalingo app name (required)
- `exclude_tables` - Array of tables to exclude from cloning (default: `[]`)
- `parallel_connections` - Number of parallel connections (default: `3`)
- `slack_webhook_url` - Slack webhook URL (default: `nil`)
- `slack_channel` - Slack channel name (default: `nil`)
- `slack_enabled` - Boolean to enable Slack notifications (default: `false`)
- `seeds_file_path` - Path to seeds file (default: `nil`)
- `postgis` - Boolean to enable PostGIS support (default: `false`)
- `logger` - Custom logger (default: `Rails.logger`)
- `temp_dir` - Temporary directory path (default: `Rails.root.join("tmp")`)

### 🔄 Migration Guide

#### For New Users
No migration needed - follow the Quick Start guide in the README.

#### For Projects Using Hardcoded Tables
If you were relying on the gem's automatic anonymization of `users`, `phone_numbers`, and `payment_methods` tables, you should now explicitly configure them:

**Before (automatic, now deprecated with warning):**
```ruby
ScalingoStagingSync.configure do |config|
  config.clone_source_scalingo_app_name = "my-app-production"
  # Tables were automatically anonymized
end
```

**After (explicit configuration):**
```ruby
ScalingoStagingSync.configure do |config|
  config.clone_source_scalingo_app_name = "my-app-production"

  config.anonymization_tables = [
    { table: "users", strategy: :user_anonymization, translation: "utilisateurs" },
    { table: "phone_numbers", strategy: :phone_anonymization, translation: "téléphones" },
    { table: "payment_methods", strategy: :payment_anonymization, translation: "moyens de paiement" }
  ]
end
```

**Note**: The gem will continue to work with automatic tables for now, but will log a deprecation warning. This behavior may be removed in a future major version.

### ⚠️ Breaking Changes

None - this is the initial release.

### 🐛 Bug Fixes

Not applicable - initial release.

### 📊 Performance Improvements

Not applicable - initial release.

### 🔐 Security

- Multi-factor production environment protection prevents accidental production usage
- Command injection protection via SQL sanitization
- Transaction-based anonymization with automatic rollback
- Verification ensures anonymization succeeded
- PII scanner detects missed sensitive data

### 📦 Dependencies

**Runtime:**
- `pg` - PostgreSQL adapter
- `rails` (>= 8.0.3) - Rails framework
- `scalingo` - Scalingo API client
- `zeitwerk` - Code autoloading

**Development:**
- `minitest` - Testing framework
- `minitest-rg` - Colored test output
- `rake` - Task automation
- `rubocop` with plugins - Code linting

### 🙏 Acknowledgments

- Built for the Scalingo community
- Thanks to all early testers and contributors
- Inspired by the need for safe, compliant staging environments

---

For detailed release notes and downloads, see: https://github.com/navidemad/scalingo-staging-sync/releases
