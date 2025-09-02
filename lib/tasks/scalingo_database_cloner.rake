# frozen_string_literal: true

namespace :scalingo_database_cloner do
  desc "Install Scalingo Database Cloner configuration"
  task :install do
    puts "Please use the Rails generator instead:"
    puts
    puts "  bundle exec rails generate scalingo_database_cloner:install"
    puts
    puts "This will create the configuration file and show setup instructions."
  end

  desc "Clone and anonymize Scalingo production database to staging"
  task clone: :environment do
    # The configuration is loaded from config/initializers/scalingo_database_cloner.rb
    coordinator = ScalingoDatabaseCloner::StagingSyncCoordinator.new
    coordinator.execute!
  end

  desc "Test Scalingo database cloner configuration and safety checks"
  task test_clone: :environment do
    ScalingoDatabaseCloner::StagingSyncTester.new.run_tests!
  end
end
