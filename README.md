# scalingo-staging-sync

[![Gem Version](https://img.shields.io/gem/v/scalingo-staging-sync)](https://rubygems.org/gems/scalingo-staging-sync)
[![Gem Downloads](https://img.shields.io/gem/dt/scalingo-staging-sync)](https://www.ruby-toolbox.com/projects/scalingo-staging-sync)
[![GitHub Workflow Status](https://img.shields.io/github/actions/workflow/status/navidemad/scalingo-staging-sync/ci.yml)](https://github.com/navidemad/scalingo-staging-sync/actions/workflows/ci.yml)
[![GitHub release](https://img.shields.io/github/v/release/navidemad/scalingo-staging-sync?color=blue&label=release)]()
[![GitHub license](https://img.shields.io/github/license/navidemad/scalingo-staging-sync?color=green)]()

[![GitHub issues](https://img.shields.io/github/issues/navidemad/scalingo-staging-sync?color=red)]()
[![GitHub stars](https://img.shields.io/github/stars/navidemad/scalingo-staging-sync?color=yellow)]()
[![GitHub forks](https://img.shields.io/github/forks/navidemad/scalingo-staging-sync?color=orange)]()
[![GitHub watchers](https://img.shields.io/github/watchers/navidemad/scalingo-staging-sync?color=blue)]()

Clone and anonymize Scalingo production databases for safe use in staging/demo environments

**Requirements:** PostgreSQL, Rails

## Quick start

Add the gem to your Gemfile inside your staging environment:
```ruby
gem 'scalingo-staging-sync', group: 'staging'
```

enable the gem with generate command to generate the default configuration

```bash
bundle exec rails generate scalingo_staging_sync:install
```

## Scheduling with Cron

Create a `cron.json` file at the root of your project to schedule the worflow:

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

This example runs the database clone every Sunday at 7:00 AM UTC.
Adjust the cron expression and dyno size according to your needs:

- **Cron format**: `minute hour day-of-month month day-of-week` Use crontab.guru to generate a cron expression
- **Size**: Choose appropriate dyno size (S, M, L, XL, 2XL, etc.) based on your database size

Note: The cron job will only run in environments where Rails.env.staging? is true.

## Workflow

The gem follows a comprehensive workflow to safely clone and anonymize production databases: [WORKFLOW.md](WORKFLOW.md)

### Key Components

- **Coordinator**: Orchestrates the entire process
- **DatabaseBackupService**: Handles Scalingo API interactions and backup downloads
- **DatabaseRestoreService**: Manages database restoration with table filtering
- **DatabaseAnonymizerService**: Anonymizes sensitive data in parallel
- **SlackNotificationService**: Provides real-time status updates

## Support

If you want to report a bug, or have ideas, feedback or questions about the gem, [let me know via GitHub issues](https://github.com/navidemad/scalingo-staging-sync/issues/new) and I will do my best to provide a helpful answer. Happy hacking!

## License

The gem is available as open source under the terms of the [MIT License](LICENSE.txt).

## Code of conduct

Everyone interacting in this project’s codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](CODE_OF_CONDUCT.md).

## Contribution guide

Pull requests are welcome!
