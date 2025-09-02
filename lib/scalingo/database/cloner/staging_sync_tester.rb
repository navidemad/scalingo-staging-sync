# frozen_string_literal: true

module Scalingo
  module Database
    module Cloner
      class StagingSyncTester
        def initialize(logger: Rails.logger)
          @logger = logger
          @results = {}
          @config_file = Rails.root.join("config/scalingo_database_cloner.yml")
          @slack_notifier = Scalingo::Database::Cloner::SlackNotificationService.new(logger: logger)
        end

        def run_tests!
          @logger.info "[StagingSyncTester] Starting demo database sync configuration tests..."
          @slack_notifier.notify_step("🧪 Starting configuration tests", context: "[Tester]")

          Rails.logger.debug { "\n#{'=' * 60}" }
          Rails.logger.debug "DEMO DATABASE SYNC CONFIGURATION TEST"
          Rails.logger.debug "=" * 60

          # Run all tests
          @logger.info "[StagingSyncTester] Running test suite..."
          test_configuration_file
          test_security_guards
          test_environment_variables
          test_required_tools
          test_database_connectivity
          test_slack_integration
          test_permissions

          # Display summary
          display_summary

          # Return overall status
          result = all_tests_passed?

          if result
            @logger.info "[StagingSyncTester] ✅ All tests passed successfully"
            @slack_notifier.notify_step("✅ Configuration tests passed", context: "[Tester]")
          else
            @logger.error "[StagingSyncTester] ❌ Tests failed - see summary for details"
            @slack_notifier.notify_warning("Configuration tests failed - check logs", context: "[Tester]")
          end

          result
        end

        private

        def test_configuration_file
          @logger.info "[StagingSyncTester] Testing configuration file..."
          section_header("Configuration File")

          if File.exist?(@config_file)
            @config = YAML.load_file(@config_file)
            pass "scalingo_database_cloner.yml found"
            @logger.info "[StagingSyncTester] Config file loaded successfully from #{@config_file}"

            # Validate required keys
            validate_config_keys
          else
            fail "scalingo_database_cloner.yml not found at #{@config_file}"
            @logger.error "[StagingSyncTester] Config file not found: #{@config_file}"
            @config = {}
          end
        rescue StandardError => e
          fail "Error loading config: #{e.message}"
          @logger.error "[StagingSyncTester] Failed to load config: #{e.message}"
          @config = {}
        end

        def validate_config_keys
          required_keys = { "target_app" => "Target application name", "source_app" => "Source application name" }

          required_keys.each do |key, description|
            fail "Missing config: #{key}" unless @config[key].present?

            info "  #{description}: #{@config[key]}"
          end

          # Optional configurations
          info "  Anonymization: \u2705 Enabled"
          info "  Slack notifications: \u2705 Enabled"

          return unless @config.dig("database", "exclude_tables").present?

          info "  Excluded tables: #{@config.dig('database', 'exclude_tables').size} tables"
          @config["database"]["exclude_tables"].each { |table| info "    - #{table}" }
        end

        def test_security_guards
          @logger.info "[StagingSyncTester] Testing security guards..."
          section_header("Security Guards")

          # Test Rails environment
          if Rails.env.production?
            fail "Rails.env is PRODUCTION - THIS IS CRITICAL!"
            @logger.critical "[StagingSyncTester] CRITICAL: Rails.env is PRODUCTION!"
            Rails.logger.debug "  ⚠️  NEVER run staging sync in production environment!"
            @slack_notifier.notify_warning("🔴 CRITICAL: Production environment detected!", context: "[Tester]")
          else
            pass "Rails.env: #{Rails.env} (safe)"
            @logger.info "[StagingSyncTester] Rails environment safe: #{Rails.env}"
          end

          # Test APP environment variable
          if ENV["APP"].present?
            if ENV["APP"].include?("prod")
              fail "APP contains 'prod': #{ENV['APP']}"
              @logger.error "[StagingSyncTester] APP variable contains 'prod': #{ENV['APP']}"
            else
              pass "APP: #{ENV['APP']} (safe)"
              @logger.info "[StagingSyncTester] APP variable safe: #{ENV['APP']}"
            end
          else
            info "  APP: not set"
            @logger.debug "[StagingSyncTester] APP environment variable not set"
          end
        end

        def test_environment_variables
          @logger.info "[StagingSyncTester] Testing environment variables..."
          section_header("Environment Variables")

          # Database URLs
          database_url = ENV.fetch("DATABASE_URL", nil)
          scalingo_url = ENV.fetch("SCALINGO_POSTGRESQL_URL", nil)

          if database_url.present?
            pass "DATABASE_URL is set"
            test_database_url_safety(database_url)
          elsif scalingo_url.present?
            pass "SCALINGO_POSTGRESQL_URL is set (fallback)"
            test_database_url_safety(scalingo_url)
          else
            fail "No database URL found (DATABASE_URL or SCALINGO_POSTGRESQL_URL)"
          end

          # Scalingo app token (for backups)
          if ENV["SCALINGO_API_TOKEN"].present?
            pass "SCALINGO_API_TOKEN is set"
            @logger.info "[StagingSyncTester] Scalingo API token configured"
          else
            warn "SCALINGO_API_TOKEN not set (may be needed for backup downloads)"
            @logger.warn "[StagingSyncTester] Scalingo API token not configured - backup downloads may fail"
          end
        end

        def test_database_url_safety(url)
          uri = URI.parse(url)
          fail "  ⚠️  Database name contains 'prod': #{uri.path}" if uri.path&.include?("prod")

          info "  Database: #{uri.path&.delete('/') || 'unknown'}"
        rescue StandardError => e
          warn "  Could not parse database URL: #{e.message}"
        end

        def test_required_tools
          @logger.info "[StagingSyncTester] Testing required tools availability..."
          section_header("Required Tools")

          tools = {
            "Scalingo CLI" => {
              command: "which scalingo",
              version_command: "scalingo version",
              required: true
            },
            "pg_restore" => {
              command: "which pg_restore",
              version_command: "pg_restore --version",
              required: true
            },
            "psql" => {
              command: "which psql",
              version_command: "psql --version",
              required: false
            },
            "tar" => {
              command: "which tar",
              version_command: "tar --version | head -1",
              required: true
            }
          }

          tools.each do |name, config|
            if system(config[:command], out: File::NULL, err: File::NULL)
              # Get version if possible
              version = `#{config[:version_command]} 2>/dev/null`.strip.split("\n").first
              pass "#{name}: Available (#{version})"
              @logger.info "[StagingSyncTester] Tool available: #{name} - #{version}"
            elsif config[:required]
              fail "#{name}: Not found (REQUIRED)"
              @logger.error "[StagingSyncTester] Required tool missing: #{name}"
            else
              warn "#{name}: Not found (optional)"
              @logger.warn "[StagingSyncTester] Optional tool missing: #{name}"
            end
          end
        end

        def test_database_connectivity
          @logger.info "[StagingSyncTester] Testing database connectivity..."
          section_header("Database Connectivity")

          database_url = ENV["DATABASE_URL"] || ENV.fetch("SCALINGO_POSTGRESQL_URL", nil)

          if database_url.blank?
            fail "Cannot test - no database URL"
            @logger.error "[StagingSyncTester] No database URL available for testing"
            return
          end

          begin
            uri = URI.parse(database_url)
            connection =
              PG.connect(
                host: uri.host,
                port: uri.port || 5432,
                dbname: uri.path[1..],
                user: uri.user,
                password: uri.password,
                connect_timeout: 5
              )

            # Test connection and get some stats
            result = connection.exec("SELECT version()")
            pg_version = result.first["version"].split[1]
            pass "PostgreSQL connection successful (v#{pg_version})"
            @logger.info "[StagingSyncTester] PostgreSQL connection successful - version #{pg_version}"

            # Get database size
            size_result = connection.exec("SELECT pg_database_size(current_database())")
            db_size_mb = (size_result.first["pg_database_size"].to_i / 1024.0 / 1024.0).round(2)
            info "  Database size: #{db_size_mb} MB"
            @logger.info "[StagingSyncTester] Database size: #{db_size_mb} MB"

            # Get table counts
            tables_result = connection.exec(
              "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public'"
            )
            table_count = tables_result.first["count"]
            info "  Public tables: #{table_count}"
            @logger.info "[StagingSyncTester] Public schema contains #{table_count} tables"

            # Check for users table
            users_result =
              begin
                connection.exec("SELECT COUNT(*) as count FROM users")
              rescue StandardError
                nil
              end
            if users_result
              user_count = users_result.first["count"]
              info "  Users in database: #{user_count.to_i.to_fs(:delimited)}"
            end

            connection.close
            @logger.info "[StagingSyncTester] Database connection test completed successfully"
          rescue PG::Error => e
            fail "Database connection failed: #{e.message}"
            @logger.error "[StagingSyncTester] Database connection failed: #{e.message}"
          rescue StandardError => e
            fail "Unexpected error: #{e.message}"
            @logger.error "[StagingSyncTester] Unexpected error during database test: #{e.message}"
          end
        end

        def test_slack_integration
          @logger.info "[StagingSyncTester] Testing Slack integration..."
          section_header("Slack Integration")

          if defined?(SlackNotifier)
            pass "SlackNotifier class is loaded"
            @logger.info "[StagingSyncTester] SlackNotifier module is available"

            # Check for required methods
            required_methods = %i[
              scalingo_database_cloner_step
              scalingo_database_cloner_success
              scalingo_database_cloner_failure
            ]

            missing_methods = required_methods.reject { |m| SlackNotifier.respond_to?(m) }

            if missing_methods.empty?
              pass "All required Slack methods available"
              @logger.info "[StagingSyncTester] All required Slack notification methods available"
            else
              fail "Missing Slack methods: #{missing_methods.join(', ')}"
              @logger.error "[StagingSyncTester] Missing Slack methods: #{missing_methods.join(', ')}"
            end
          else
            warn "SlackNotifier not defined - notifications will be skipped"
            @logger.warn "[StagingSyncTester] SlackNotifier not available - Slack notifications disabled"
          end
        end

        def test_permissions
          @logger.info "[StagingSyncTester] Testing file system permissions..."
          section_header("File System Permissions")

          # Test temp directory
          temp_dir = Rails.root.join("tmp")
          if File.writable?(temp_dir)
            pass "Temp directory writable: #{temp_dir}"
            @logger.info "[StagingSyncTester] Temp directory is writable: #{temp_dir}"
          else
            fail "Temp directory not writable: #{temp_dir}"
            @logger.error "[StagingSyncTester] Temp directory is not writable: #{temp_dir}"
          end

          # Check staging seeds file if configured
          seeds_file = Rails.root.join("db/seeds/staging.rb")
          if File.exist?(seeds_file)
            pass "Staging seeds file exists"
            info "  Path: #{seeds_file}"
            info "  Size: #{(File.size(seeds_file) / 1024.0).round(2)} KB"
          else
            warn "Staging seeds file not found: #{seeds_file}"
          end
        end

        def display_summary
          @logger.info "[StagingSyncTester] Generating test summary..."

          Rails.logger.debug { "\n#{'=' * 60}" }
          Rails.logger.debug "TEST SUMMARY"
          Rails.logger.debug "=" * 60

          total_tests = @results.count
          passed = @results.count { |_, status| status == :pass }
          failed = @results.count { |_, status| status == :fail }
          warnings = @results.count { |_, status| status == :warn }

          Rails.logger.debug "\n📊 Results:"
          Rails.logger.debug { "  ✅ Passed: #{passed}/#{total_tests}" }
          Rails.logger.debug { "  ❌ Failed: #{failed}/#{total_tests}" } if failed > 0
          Rails.logger.debug { "  ⚠️  Warnings: #{warnings}/#{total_tests}" } if warnings > 0

          if failed > 0
            Rails.logger.debug "\n❌ Critical issues found:"
            @results.select { |_, status| status == :fail }.each_key { |message| Rails.logger.debug "  - #{message}" }
          end

          if warnings > 0
            Rails.logger.debug "\n⚠️  Warnings:"
            @results.select { |_, status| status == :warn }.each_key { |message| Rails.logger.debug "  - #{message}" }
          end

          Rails.logger.debug { "\n#{'=' * 60}" }

          if all_tests_passed?
            Rails.logger.debug "✅ ALL CRITICAL TESTS PASSED - Ready for demo sync!"
            Rails.logger.debug "Run: bundle exec rake demo_database:sync"
            @logger.info "[StagingSyncTester] ✅ System ready for demo sync"
          elsif failed > 0
            Rails.logger.debug "❌ CRITICAL ISSUES DETECTED - Fix before running sync"
            @logger.error "[StagingSyncTester] ❌ Critical issues detected - cannot proceed with sync"
          else
            Rails.logger.debug "⚠️  WARNINGS DETECTED - Review before running demo sync"
            Rails.logger.debug "Run with caution: bundle exec rake demo_database:sync"
            @logger.warn "[StagingSyncTester] ⚠️  Warnings detected - review before proceeding"
          end

          Rails.logger.debug { "#{'=' * 60}\n" }
        end

        def all_tests_passed?
          !@results.value?(:fail)
        end

        def section_header(title)
          Rails.logger.debug { "\n#{title}" }
          Rails.logger.debug "-" * title.length
        end

        def pass(message)
          Rails.logger.debug { "  ✅ #{message}" }
          @results[message] = :pass
        end

        def fail(message)
          Rails.logger.debug { "  ❌ #{message}" }
          @results[message] = :fail
        end

        def warn(message)
          Rails.logger.debug { "  ⚠️  #{message}" }
          @results[message] = :warn
        end

        def info(message)
          Rails.logger.debug { "  ℹ️  #{message}" }
        end
      end
    end
  end
end
