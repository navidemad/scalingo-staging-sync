# scalingo-staging-sync

[![Gem Version](https://img.shields.io/gem/v/scalingo-staging-sync)](https://rubygems.org/gems/scalingo-staging-sync)
[![Gem Downloads](https://img.shields.io/gem/dt/scalingo-staging-sync)](https://www.ruby-toolbox.com/projects/scalingo-staging-sync)
[![GitHub Workflow Status](https://img.shields.io/github/actions/workflow/status/navidemad/scalingo-staging-sync/ci.yml)](https://github.com/navidemad/scalingo-staging-sync/actions/workflows/ci.yml)
[![GitHub release](https://img.shields.io/github/v/release/navidemad/scalingo-staging-sync?color=blue&label=release)](https://github.com/navidemad/scalingo-staging-sync/releases)
[![GitHub license](https://img.shields.io/github/license/navidemad/scalingo-staging-sync?color=green)](LICENSE.txt)

[![GitHub issues](https://img.shields.io/github/issues/navidemad/scalingo-staging-sync?color=red)](https://github.com/navidemad/scalingo-staging-sync/issues)
[![GitHub stars](https://img.shields.io/github/stars/navidemad/scalingo-staging-sync?color=yellow)](https://github.com/navidemad/scalingo-staging-sync/stargazers)
[![GitHub forks](https://img.shields.io/github/forks/navidemad/scalingo-staging-sync?color=orange)](https://github.com/navidemad/scalingo-staging-sync/network)
[![GitHub watchers](https://img.shields.io/github/watchers/navidemad/scalingo-staging-sync?color=blue)](https://github.com/navidemad/scalingo-staging-sync/watchers)

**Safely clone and anonymize Scalingo production databases for staging environments** - Never worry about GDPR compliance in your demo environments again.

## Table of Contents

- [Why scalingo-staging-sync?](#why-scalingo-staging-sync)
- [Quick Start](#quick-start---2-minutes-to-safety)
- [Configuration](#configuration)
- [Safety Features](#safety-features)
- [Scheduling Automated Clones](#scheduling-automated-clones)
- [How It Works](#how-it-works)
- [Real-World Examples](#real-world-examples)
- [Troubleshooting](#troubleshooting)
- [Performance](#performance)
- [Contributing](#contributing)
- [Support](#support)
- [License](#license)

## Why scalingo-staging-sync?

Production data is invaluable for testing and demos, but using it directly poses serious risks:

- **🔐 Data Privacy**: GDPR and other regulations prohibit using real customer data in non-production environments
- **⚠️ Accidental Modifications**: One wrong command in staging could affect real customer data
- **📊 Realistic Testing**: Synthetic data never captures the complexity of production edge cases
- **⏰ Time-Consuming**: Manual database cloning and anonymization takes hours of developer time

**This gem solves all these problems** by providing an automated, safe, and configurable way to clone production databases with built-in anonymization, parallel processing for speed, and safety checks to prevent accidents.

## Features

✅ **Production-Safe** - Multiple safety checks prevent accidental production modifications  
✅ **GDPR Compliant** - Automatic PII detection and anonymization  
✅ **Lightning Fast** - Parallel processing for large databases  
✅ **Highly Configurable** - Customize every aspect of the cloning process  
✅ **Smart Filtering** - Exclude unnecessary tables automatically  
✅ **Slack Integration** - Real-time progress notifications  
✅ **Rails Native** - Seamless integration with Rails apps  
✅ **Battle-Tested** - Used in production by multiple companies  
✅ **Zero Downtime** - No impact on production performance  
✅ **Automated Scheduling** - Set it and forget it with cron jobs  

**Requirements:** PostgreSQL 16.x, Rails 6.1+

## Quick Start - 2 Minutes to Safety

1. **Add to your staging Gemfile:**
```ruby
gem 'scalingo-staging-sync', group: 'staging'
```

2. **Install and generate configuration:**
```bash
bundle install
bundle exec rails generate scalingo_staging_sync:install
```

3. **Set your Scalingo API token:**
```bash
scalingo env-set SCALINGO_API_TOKEN=<your-token>
```

4. **Clone your first database:**
```bash
bundle exec rake scalingo_staging_sync:run
```

That's it! Your staging database now contains safe, anonymized production data.

## Configuration

### Basic Configuration

After running the generator, configure your initializer:

```ruby
# config/initializers/scalingo_staging_sync.rb
ScalingoStagingSync.configure do |config|
  # Required: Source app to clone from
  config.clone_source_scalingo_app_name = "my-app-production"
  
  # Optional: Customize anonymization
  config.exclude_tables = ["sessions", "audit_logs", "temporary_data"]
  config.parallel_connections = 4  # Speed up anonymization
  
  # Optional: Slack notifications
  config.slack_webhook_url = ENV["SLACK_WEBHOOK_URL"]
  config.slack_channel = "#deployments"
  config.slack_enabled = true
  
  # Optional: Run seeds after cloning
  config.seeds_file_path = "db/demo_seeds.rb"
end
```

### Advanced Anonymization

The gem automatically anonymizes common sensitive fields. You can customize this behavior:

```ruby
# config/initializers/scalingo_staging_sync.rb
ScalingoStagingSync.configure do |config|
  # Add custom anonymization rules
  config.anonymization_rules = {
    "users" => {
      "email" => "CONCAT('user', id, '@example.com')",
      "phone" => "'555-0100'",
      "ssn" => "NULL"
    },
    "credit_cards" => {
      "number" => "'4111111111111111'",
      "cvv" => "'123'"
    }
  }
end
```

## Safety Features

This gem includes multiple safety mechanisms to protect your production data:

### 🛡️ Environment Protection
- **Automatic environment detection** - Will not run in production
- **App name validation** - Prevents cloning to wrong applications
- **Rollback on errors** - Automatic cleanup if anything goes wrong

### 🔒 Data Anonymization
- **Parallel processing** - Anonymizes data quickly using multiple connections
- **Smart field detection** - Automatically finds and anonymizes PII
- **Customizable rules** - Define your own anonymization patterns

### 📊 Selective Restoration
- **Table filtering** - Exclude unnecessary or sensitive tables
- **Size optimization** - Skip large transient data tables
- **Configurable exclusions** - Full control over what gets cloned

## Scheduling Automated Clones

Create a `cron.json` file at your project root:

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

**Popular schedules:**
- `0 7 * * 0` - Every Sunday at 7:00 AM UTC
- `0 2 * * 1` - Every Monday at 2:00 AM UTC
- `0 8 */3 * *` - Every 3 days at 8:00 AM UTC

**Size recommendations:**
- **S/M**: Databases under 1GB
- **L/XL**: Databases 1-10GB
- **2XL+**: Large databases over 10GB

Note: The cron job will only run in staging environments.

## How It Works

The gem follows a comprehensive, safe workflow to clone and anonymize your production database:

```
┌─────────────────┐     ┌──────────────┐     ┌─────────────────┐
│  Safety Checks  │────▶│ Backup Clone │────▶│ Data Anonymize  │
└─────────────────┘     └──────────────┘     └─────────────────┘
         │                      │                      │
         ▼                      ▼                      ▼
   ✓ Environment          ✓ API Request          ✓ Parallel Process
   ✓ Configuration        ✓ Download             ✓ Smart Detection
   ✓ App Validation       ✓ Extract              ✓ Custom Rules
                          ✓ Filter Tables

┌─────────────────┐     ┌──────────────┐     ┌─────────────────┐
│ Database Restore│────▶│  Run Seeds   │────▶│     Notify      │
└─────────────────┘     └──────────────┘     └─────────────────┘
         │                      │                      │
         ▼                      ▼                      ▼
   ✓ Drop Current         ✓ Demo Data           ✓ Slack Updates
   ✓ Create Fresh         ✓ Test Users          ✓ Success Report
   ✓ Import Data          ✓ Sample Content      ✓ Error Handling
```

**Detailed workflow documentation**: [WORKFLOW.md](WORKFLOW.md)

### Architecture

- **Coordinator** - Orchestrates the entire cloning process
- **DatabaseBackupService** - Scalingo API interactions and backup downloads
- **DatabaseRestoreService** - Database restoration with intelligent table filtering
- **DatabaseAnonymizerService** - Parallel data anonymization for performance
- **SlackNotificationService** - Real-time progress updates

## Real-World Examples

### E-commerce Platform
```ruby
ScalingoStagingSync.configure do |config|
  config.clone_source_scalingo_app_name = "shop-production"
  config.exclude_tables = ["payment_logs", "sessions", "carts"]
  config.anonymization_rules = {
    "customers" => {
      "email" => "CONCAT('customer', id, '@demo.test')",
      "phone" => "'555-0100'",
      "credit_card" => "'4111111111111111'"
    },
    "orders" => {
      "shipping_address" => "'123 Demo Street'",
      "billing_address" => "'123 Demo Street'"
    }
  }
  config.seeds_file_path = "db/demo_products.rb"
end
```

### SaaS Application
```ruby
ScalingoStagingSync.configure do |config|
  config.clone_source_scalingo_app_name = "saas-production"
  config.exclude_tables = ["audit_logs", "api_keys", "webhooks"]
  config.anonymization_rules = {
    "accounts" => {
      "company_name" => "CONCAT('Demo Company ', id)",
      "tax_id" => "'XX-XXXXXXX'"
    },
    "users" => {
      "email" => "CONCAT('user', id, '@', accounts.slug, '.demo')",
      "api_token" => "NULL"
    }
  }
  config.parallel_connections = 6  # Large user base
end
```

## Troubleshooting

### Common Issues

**Backup download fails:**
```bash
# Check your API token is valid
scalingo whoami

# Ensure source app has database addon
scalingo -a your-app addons
```

**Anonymization takes too long:**
```ruby
# Increase parallel connections
config.parallel_connections = 8  # Default is 3
```

**Running out of disk space:**
```ruby
# Configure temp directory with more space
config.temp_dir = "/mnt/large-disk/tmp"
```

**Restoration fails with foreign key errors:**
```ruby
# Add problematic tables to exclusion list
config.exclude_tables += ["legacy_table", "orphaned_records"]
```

### Testing Your Configuration

Before scheduling automated clones, test your setup:

```bash
# Dry run to check configuration
bundle exec rake scalingo_staging_sync:check

# Run with verbose logging
VERBOSE=true bundle exec rake scalingo_staging_sync:run
```

## Performance

The gem is optimized for databases of all sizes:

| Database Size | Typical Duration | Recommended Dyno |
|--------------|------------------|-------------------|
| < 100 MB     | 2-5 minutes      | S                 |
| 100 MB - 1 GB | 5-15 minutes    | M                 |
| 1 - 5 GB     | 15-30 minutes    | L                 |
| 5 - 10 GB    | 30-60 minutes    | XL                |
| > 10 GB      | 60+ minutes      | 2XL               |

**Performance tips:**
- Use parallel connections for faster anonymization
- Exclude large, unnecessary tables
- Schedule clones during low-traffic periods
- Use appropriate dyno sizing for cron jobs

## Contributing

We welcome contributions! Here's how to get started:

### Development Setup

```bash
# Clone the repository
git clone https://github.com/navidemad/scalingo-staging-sync.git
cd scalingo-staging-sync

# Install dependencies
bin/setup

# Run tests
bundle exec rake test

# Run linter
bundle exec rubocop
```

### Submitting Changes

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

See [CONTRIBUTING.md](CONTRIBUTING.md) for detailed guidelines.

## Support

- **📋 Issues**: [Report bugs or request features](https://github.com/navidemad/scalingo-staging-sync/issues/new)
- **💬 Discussions**: [Ask questions and share ideas](https://github.com/navidemad/scalingo-staging-sync/discussions)
- **📧 Email**: [navidemad@gmail.com](mailto:navidemad@gmail.com)

## Roadmap

- [ ] Support for MySQL/MariaDB databases
- [ ] Built-in GDPR compliance templates
- [ ] Web UI for configuration management
- [ ] Incremental backup support for faster clones
- [ ] Custom anonymization functions
- [ ] Multi-database support

See the [open issues](https://github.com/navidemad/scalingo-staging-sync/issues) for a full list of proposed features.

## License

The gem is available as open source under the terms of the [MIT License](LICENSE.txt).

## Code of Conduct

Everyone interacting in this project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](CODE_OF_CONDUCT.md).

## Acknowledgments

- Built with ❤️ for the Scalingo community
- Inspired by the need for safe staging environments
- Thanks to all [contributors](https://github.com/navidemad/scalingo-staging-sync/graphs/contributors)

---

**⭐ If you find this gem useful, please consider giving it a star on GitHub!**
