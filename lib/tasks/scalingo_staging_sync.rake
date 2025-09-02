# frozen_string_literal: true

namespace :scalingo_staging_sync do
  desc "Install Scalingo Staging Sync configuration"
  task :install do
    puts "Please use the Rails generator instead:"
    puts
    puts "  bundle exec rails generate scalingo_staging_sync:install"
    puts
    puts "This will create the configuration file and show setup instructions."
  end

  desc "Sync and anonymize Scalingo production database to staging"
  task run: :environment do
    # The configuration is loaded from config/initializers/scalingo_staging_sync.rb
    coordinator = ScalingoStagingSync::Services::Coordinator.new
    coordinator.execute!
  end

  desc "Check Scalingo staging sync configuration and safety checks"
  task check: :environment do
    ScalingoStagingSync::Testing::Tester.new.run_tests!
  end
end
