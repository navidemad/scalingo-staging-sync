# frozen_string_literal: true

namespace :staging_sync do
  desc "Install Scalingo Staging Sync configuration"
  task :install do
    puts "Please use the Rails generator instead:"
    puts
    puts "  bundle exec rails generate staging_sync:install"
    puts
    puts "This will create the configuration file and show setup instructions."
  end

  desc "Sync and anonymize Scalingo production database to staging"
  task sync: :environment do
    # The configuration is loaded from config/initializers/scalingo_staging_sync.rb
    coordinator = Scalingo::StagingSync::Coordinator.new
    coordinator.execute!
  end

  desc "Test Scalingo staging sync configuration and safety checks"
  task test_sync: :environment do
    Scalingo::StagingSync::Tester.new.run_tests!
  end
end
