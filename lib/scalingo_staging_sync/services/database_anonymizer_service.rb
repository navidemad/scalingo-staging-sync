# frozen_string_literal: true

require_relative "../database/anonymization_queries"
require_relative "../database/anonymization_strategies"
require_relative "../support/parallel_processor"
require_relative "../database/table_anonymizer"
require_relative "../database/transaction_helpers"
require_relative "../database/column_validator"
require_relative "../database/anonymization_verifier"
require_relative "../database/pii_scanner"
require_relative "../database/anonymization_audit"

module ScalingoStagingSync
  module Services
    class DatabaseAnonymizerService
      include Database::AnonymizationQueries
      include Support::ParallelProcessor
      include Database::TableAnonymizer
      include Database::TransactionHelpers
      include Database::ColumnValidator
      include Database::AnonymizationVerifier
      include Database::PiiScanner
      include Database::AnonymizationAudit

      # Legacy default tables (deprecated - use configuration instead)
      LEGACY_DEFAULT_TABLES = [
        { table: "users", strategy: :user_anonymization, translation: "utilisateurs" },
        { table: "phone_numbers", strategy: :phone_anonymization, translation: "téléphones" },
        { table: "payment_methods", strategy: :payment_anonymization, translation: "moyens de paiement" }
      ].freeze

      def initialize(database_url, parallel_connections: 3, logger: Rails.logger)
        if ScalingoStagingSync.configuration.postgis
          # Store both versions: postgis:// for Rails, postgres:// for PG.connect
          @database_url = database_url.sub(/^postgres/, "postgis") # For Rails (handles PostGIS types)
          @pg_url = database_url.sub(/^postgis/, "postgres") # For PG.connect
        else
          @database_url = database_url
          @pg_url = database_url
        end
        @parallel_connections = parallel_connections
        @logger = logger
        @slack_notifier = ScalingoStagingSync::Services::SlackNotificationService.new(logger: logger)
        @anonymization_tables = load_anonymization_tables
        @work_queues = generate_work_queues
        @audit_records = []
        @verification_results = {}
      end

      def anonymize!
        log_start_anonymization
        start_time = Time.current

        # Run pre-anonymization checks
        run_pre_anonymization_checks if ScalingoStagingSync.configuration.verify_anonymization

        # Run PII scan before anonymization
        run_pii_scan_before if ScalingoStagingSync.configuration.run_pii_scan

        # Run anonymization
        threads = create_anonymization_threads
        wait_for_threads(threads)

        # Run final verification and generate audit report
        run_final_verification if ScalingoStagingSync.configuration.verify_anonymization
        generate_final_audit_report if ScalingoStagingSync.configuration.anonymization_audit_file

        report_completion(start_time)
      end

      private

      def establish_connection
        uri = URI.parse(@pg_url)
        @logger.debug(
          "[DatabaseAnonymizerService] Establishing PG connection to " \
          "#{uri.host}:#{uri.port} database: #{uri.path[1..]}"
        )
        connection =
          PG.connect(host: uri.host, port: uri.port, dbname: uri.path[1..], user: uri.user, password: uri.password)
        @logger.debug "[DatabaseAnonymizerService] PG connection established successfully"
        connection
      rescue PG::Error => e
        @logger.error "[DatabaseAnonymizerService] Failed to establish connection: #{e.message}"
        @slack_notifier.anonymizer_error("Échec connexion base de données")
        raise
      end

      def anonymize_table(connection, table)
        @logger.info "[DatabaseAnonymizerService] Starting anonymization of table: #{table}"
        start_time = Time.current

        # Capture pre-anonymization state for audit
        if ScalingoStagingSync.configuration.anonymization_audit_file
          before_state = capture_pre_anonymization_state(
            connection,
            table
          )
        end

        rows_affected = execute_anonymization_query(connection, table)

        # Capture post-anonymization state and verify
        if ScalingoStagingSync.configuration.verify_anonymization
          verification_result = verify_table_anonymization(connection, table)
          @verification_results[table] = verification_result

          # Handle verification failure
          if !verification_result[:success] && ScalingoStagingSync.configuration.fail_on_verification_error
            log_verification_failure(table, verification_result)
            raise PG::Error, "Verification failed for #{table}: #{verification_result[:issues].join(', ')}"
          elsif !verification_result[:success]
            log_verification_failure(table, verification_result)
          end
        end

        # Capture post-anonymization state for audit
        if ScalingoStagingSync.configuration.anonymization_audit_file
          after_state = capture_post_anonymization_state(connection, table, rows_affected)
          @audit_records << { before: before_state, after: after_state }
        end

        report_table_completion(table, rows_affected, start_time)
      rescue PG::Error => e
        handle_anonymization_error(table, e)
      end

      def execute_anonymization_query(connection, table)
        table_config = find_table_config(table)
        return 0 unless table_config

        query = build_anonymization_query(table_config)
        return 0 unless query

        # Extract WHERE clause for verification
        where_clause = extract_where_clause(query)

        # Execute with transaction, retry, and verification
        with_retry(
          max_attempts: ScalingoStagingSync.configuration.anonymization_retry_attempts,
          base_delay: ScalingoStagingSync.configuration.anonymization_retry_delay,
          table_name: table
        ) do
          with_transaction(connection, savepoint_name: "anon_#{table}") do
            @logger.info "[DatabaseAnonymizerService] Anonymizing #{table} table..."
            result = connection.exec(query)
            rows = result.cmd_tuples

            # Verify the anonymization if verification is enabled
            if ScalingoStagingSync.configuration.verify_anonymization && !verify_anonymization(
              connection,
              table,
              rows,
              where_clause: where_clause
            )
              raise PG::Error, "Verification failed for #{table}"
            end

            @logger.info "[DatabaseAnonymizerService] #{table.capitalize} table: #{rows} rows anonymized"
            rows
          end
        end
      rescue PG::Error => e
        @logger.error "[DatabaseAnonymizerService] Error anonymizing #{table}: #{e.message}"
        raise
      end

      # Table anonymization methods are provided by TableAnonymizer module

      def report_table_completion(table, rows_affected, start_time)
        duration = (Time.current - start_time).round(2)
        @logger.info "[DatabaseAnonymizerService] ✓ Anonymized #{table} - #{rows_affected} rows in #{duration}s"

        table_config = find_table_config(table)
        table_name_fr = table_config&.dig(:translation) || table
        @slack_notifier.anonymizer_step("✓ #{table_name_fr.capitalize}: #{rows_affected} lignes anonymisées")
      end

      def handle_anonymization_error(table, error)
        @logger.error "[DatabaseAnonymizerService] Failed to anonymize #{table}: #{error.message}"
        @slack_notifier.anonymizer_error("Échec anonymisation #{table}")
        raise
      end

      def log_start_anonymization
        @logger.info(
          "[DatabaseAnonymizerService] Starting parallel anonymization with #{@parallel_connections} connections..."
        )
        @slack_notifier.anonymizer_step(
          "🔐 Anonymisation des données (#{@parallel_connections} connexions parallèles)"
        )
        log_work_queues
      end

      def log_work_queues
        @logger.info "[DatabaseAnonymizerService] Work queues configured:"
        @work_queues.each { |connection_id, tables| @logger.info "  - #{connection_id}: #{tables.join(', ')}" }
      end

      def report_completion(start_time)
        duration = Time.current - start_time
        @logger.info "[DatabaseAnonymizerService] ✅ Parallel anonymization completed in #{duration.round(2)}s"
        @slack_notifier.anonymizer_step("✅ Anonymisation terminée (#{duration.round(2)}s)")
      end

      # Load anonymization tables from configuration or use legacy defaults
      def load_anonymization_tables
        config_tables = ScalingoStagingSync.configuration.anonymization_tables

        if config_tables.empty?
          @logger.warn(
            "[DatabaseAnonymizerService] DEPRECATION WARNING: Using hardcoded anonymization tables. " \
            "Please configure `anonymization_tables` in your initializer. " \
            "See configuration documentation for examples."
          )
          return LEGACY_DEFAULT_TABLES
        end

        validate_anonymization_tables!(config_tables)
        config_tables
      end

      # Validate anonymization table configuration
      def validate_anonymization_tables!(tables)
        tables.each do |table_config|
          raise ArgumentError, "anonymization_tables entry missing required :table key: #{table_config.inspect}" unless table_config[:table]

          if table_config[:strategy] && table_config[:query]
            raise ArgumentError,
                  "Table '#{table_config[:table]}' cannot have both :strategy and :query. Choose one."
          end

          next unless table_config[:strategy]

          next if Database::AnonymizationStrategies.strategy_exists?(table_config[:strategy])

          raise ArgumentError,
                "Unknown anonymization strategy '#{table_config[:strategy]}' for table '#{table_config[:table]}'. " \
                "Available strategies: #{available_strategies.join(', ')}"
        end
      end

      # Generate work queues based on parallel_connections configuration
      def generate_work_queues
        tables = @anonymization_tables.map { |t| t[:table] }
        num_connections = @parallel_connections

        # Distribute tables evenly across connections
        queues = {}
        tables.each_with_index do |table, index|
          connection_id = :"connection_#{(index % num_connections) + 1}"
          queues[connection_id] ||= []
          queues[connection_id] << table
        end

        queues
      end

      # Find table configuration by table name
      def find_table_config(table_name)
        @anonymization_tables.find { |t| t[:table] == table_name }
      end

      # Build anonymization query for a table
      def build_anonymization_query(table_config)
        table = table_config[:table]

        # If custom query provided, use it
        return add_condition_to_query(table_config[:query], table_config[:condition]) if table_config[:query]

        # If strategy provided, use it
        if table_config[:strategy]
          strategy = Database::AnonymizationStrategies.get_strategy(table_config[:strategy])
          unless strategy
            @logger.error "[DatabaseAnonymizerService] Strategy '#{table_config[:strategy]}' not found for #{table}"
            return nil
          end

          query = strategy.call(table, table_config[:condition])
          return add_condition_to_query(query, table_config[:condition])
        end

        # No strategy or query - try legacy method
        legacy_query = try_legacy_anonymization_query(table)
        if legacy_query
          @logger.warn(
            "[DatabaseAnonymizerService] Using legacy query method for #{table}. " \
            "Consider adding a strategy to your configuration."
          )
          return legacy_query
        end

        @logger.error "[DatabaseAnonymizerService] No anonymization strategy or query defined for table: #{table}"
        nil
      end

      # Add condition to query if provided
      def add_condition_to_query(query, condition)
        return query unless condition

        # If query already has WHERE clause, append with AND
        if query.match?(/WHERE/i)
          query.sub(/WHERE/i, "WHERE (#{condition}) AND")
        else
          "#{query} WHERE #{condition}"
        end
      end

      # Try to use legacy anonymization query methods
      def try_legacy_anonymization_query(table)
        case table
        when "users"
          users_anonymization_query
        when "phone_numbers"
          phone_numbers_anonymization_query
        when "payment_methods"
          payment_methods_anonymization_query
        end
      end

      # List available strategies
      def available_strategies
        Database::AnonymizationStrategies.custom_strategies.keys +
          %i[user_anonymization phone_anonymization payment_anonymization email_anonymization address_anonymization]
      end

      # Extract WHERE clause from SQL query for verification
      def extract_where_clause(query)
        match = query.match(/WHERE\s+(.+?)(?:;|\z)/mi)
        match ? match[1].strip : nil
      end

      # Pre-anonymization checks
      def run_pre_anonymization_checks
        @logger.info "[DatabaseAnonymizerService] Running pre-anonymization column validation..."
        connection = establish_connection

        validation_result = validate_all_anonymization_columns(connection)

        unless validation_result[:success]
          @logger.error "[DatabaseAnonymizerService] Column validation failed!"
          validation_result[:validation_results].each do |table, result|
            next if result[:success]

            @logger.error "  Table #{table}: #{result[:errors].join(', ')}"
            @slack_notifier.anonymizer_error("Validation échouée pour #{table}")
          end

          raise ArgumentError, "Required columns missing for anonymization. See logs for details."
        end

        @logger.info "[DatabaseAnonymizerService] ✓ All required columns exist"
        @slack_notifier.anonymizer_step("✓ Validation des colonnes réussie")
      ensure
        connection&.close
      end

      # Run PII scan before anonymization
      def run_pii_scan_before
        @logger.info "[DatabaseAnonymizerService] Scanning for unanonymized PII columns..."
        connection = establish_connection

        anonymized_tables = @anonymization_tables.map { |t| t[:table] }
        scan_result = scan_for_unanonymized_pii(connection, anonymized_tables)

        if scan_result[:warnings].any?
          @logger.warn "[DatabaseAnonymizerService] PII scan found potential issues:"
          scan_result[:warnings].each { |warning| @logger.warn "  - #{warning}" }
          @slack_notifier.anonymizer_step("⚠️  PII détecté dans #{scan_result[:potential_pii].size} table(s)")
        else
          @logger.info "[DatabaseAnonymizerService] ✓ No unanonymized PII columns detected"
        end
      ensure
        connection&.close
      end

      # Run final verification after all anonymization
      def run_final_verification
        @logger.info "[DatabaseAnonymizerService] Running final anonymization verification..."

        failed_tables = @verification_results.reject { |_table, result| result[:success] }

        if failed_tables.any?
          @logger.error "[DatabaseAnonymizerService] ❌ Verification failed for #{failed_tables.size} table(s):"
          failed_tables.each do |table, result|
            @logger.error "  #{table}: #{result[:issues].join(', ')}"
          end
          @slack_notifier.anonymizer_error("Vérification échouée pour #{failed_tables.size} table(s)")
        else
          @logger.info "[DatabaseAnonymizerService] ✅ All tables passed verification"
          @slack_notifier.anonymizer_step("✅ Vérification réussie pour toutes les tables")
        end
      end

      # Generate final audit report
      def generate_final_audit_report
        @logger.info "[DatabaseAnonymizerService] Generating anonymization audit report..."
        connection = establish_connection

        # Run final PII scan
        anonymized_tables = @anonymization_tables.map { |t| t[:table] }
        pii_scan_results = scan_for_unanonymized_pii(connection, anonymized_tables)

        # Generate full report
        report = generate_audit_report(@audit_records, @verification_results, pii_scan_results)

        # Save report
        audit_file = ScalingoStagingSync.configuration.anonymization_audit_file
        saved_files = save_audit_report(report, audit_file)

        @logger.info "[DatabaseAnonymizerService] ✅ Audit report saved:"
        @logger.info "  JSON: #{saved_files[:json]}"
        @logger.info "  Text: #{saved_files[:text]}"
        @slack_notifier.anonymizer_step("✅ Rapport d'audit généré")
      ensure
        connection&.close
      end

      # Log verification failure
      def log_verification_failure(table, result)
        @logger.error "[DatabaseAnonymizerService] ❌ Verification failed for #{table}:"

        result[:issues].each do |issue|
          @logger.error "  ISSUE: #{issue}"
        end

        result[:warnings].each do |warning|
          @logger.warn "  WARNING: #{warning}"
        end

        @slack_notifier.anonymizer_error("Vérification échouée: #{table}")
      end
    end
  end
end
