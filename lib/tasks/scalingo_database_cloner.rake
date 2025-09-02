namespace :scalingo_database_cloner do
  desc "Install"
  task :install do
    puts "LogBench Configuration Instructions:"
    puts
    puts "LogBench is automatically enabled in development!"
    puts "Just restart your Rails server and it will work."
    puts
    puts "For customization or other environments, see:"
    puts "https://github.com/silva96/log_bench#configuration"
  end

  desc "Clone and anonymize Scalingo production database to staging"
  task clone: :environment do
    # The configuration is loaded from config/initializers/scalingo_database_cloner.rb
    # For backward compatibility, also check for legacy config file
    legacy_config_file = Rails.root.join("config/demo_database_sync.yml")

    if File.exist?(legacy_config_file)
      # Legacy support: Load configuration from YAML file
      config = YAML.load_file(legacy_config_file)
      coordinator = ScalingoDatabaseCloner::StagingSyncCoordinator.new(config)
    else
      # Use the configured settings from the initializer
      coordinator = ScalingoDatabaseCloner::StagingSyncCoordinator.new
    end

    coordinator.execute!
  end

  desc "Test Scalingo database cloner configuration and safety checks"
  task test_clone: :environment do
    ScalingoDatabaseCloner::StagingSyncTester.new.run_tests!
  end
end
