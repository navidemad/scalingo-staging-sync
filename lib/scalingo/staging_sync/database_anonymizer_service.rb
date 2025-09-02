# frozen_string_literal: true

require_relative "anonymization_queries"
require_relative "parallel_processor"
require_relative "table_anonymizer"

module Scalingo
  module StagingSync
    class DatabaseAnonymizerService
      include AnonymizationQueries
      include ParallelProcessor
      include TableAnonymizer

      # Define anonymization work queues for parallel processing
      WORK_QUEUES = {
        connection_1: ["users"],
        connection_2: ["phone_numbers"],
        connection_3: ["payment_methods"]
      }.freeze

      # French translations for Slack notifications
      TABLE_NAME_TRANSLATIONS = {
        "users" => "utilisateurs",
        "phone_numbers" => "téléphones",
        "payment_methods" => "moyens de paiement"
      }.freeze

      def initialize(database_url, parallel_connections: 3, logger: Rails.logger)
        # Store both versions: postgis:// for Rails, postgres:// for PG.connect
        @database_url = database_url.sub(/^postgres/, "postgis") # For Rails (handles PostGIS types)
        @pg_url = database_url.sub(/^postgis/, "postgres") # For PG.connect
        @parallel_connections = parallel_connections
        @logger = logger
        @slack_notifier = Scalingo::StagingSync::SlackNotificationService.new(logger: logger)
      end

      def anonymize!
        log_start_anonymization
        start_time = Time.zone.now

        threads = create_anonymization_threads
        wait_for_threads(threads)

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
        start_time = Time.zone.now

        rows_affected = execute_anonymization_query(connection, table)
        report_table_completion(table, rows_affected, start_time)
      rescue PG::Error => e
        handle_anonymization_error(table, e)
      end

      def execute_anonymization_query(connection, table)
        case table
        when "users"
          anonymize_users_table(connection)
        when "phone_numbers"
          anonymize_phone_numbers_table(connection)
        when "payment_methods"
          anonymize_payment_methods_table(connection)
        else
          handle_unknown_table(table)
          0
        end
      end

      # Table anonymization methods are provided by TableAnonymizer module

      def report_table_completion(table, rows_affected, start_time)
        duration = (Time.zone.now - start_time).round(2)
        @logger.info "[DatabaseAnonymizerService] ✓ Anonymized #{table} - #{rows_affected} rows in #{duration}s"

        table_name_fr = TABLE_NAME_TRANSLATIONS[table] || table
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
        WORK_QUEUES.each { |connection_id, tables| @logger.info "  - #{connection_id}: #{tables.join(', ')}" }
      end

      def report_completion(start_time)
        duration = Time.zone.now - start_time
        @logger.info "[DatabaseAnonymizerService] ✅ Parallel anonymization completed in #{duration.round(2)}s"
        @slack_notifier.anonymizer_step("✅ Anonymisation terminée (#{duration.round(2)}s)")
      end
    end
  end
end
