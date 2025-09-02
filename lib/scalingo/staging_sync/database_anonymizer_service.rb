# frozen_string_literal: true

module Scalingo
  module StagingSync
    class DatabaseAnonymizerService
      def initialize(database_url, parallel_connections: 3, logger: Rails.logger)
        # Store both versions: postgis:// for Rails, postgres:// for PG.connect
        @database_url = database_url.sub(/^postgres/, "postgis") # For Rails (handles PostGIS types)
        @pg_url = database_url.sub(/^postgis/, "postgres") # For PG.connect
        @parallel_connections = parallel_connections
        @logger = logger
        @slack_notifier = Scalingo::StagingSync::SlackNotificationService.new(logger: logger)
      end

      def anonymize!
        @logger.info(
          "[DatabaseAnonymizerService] Starting parallel anonymization with #{@parallel_connections} connections..."
        )
        @slack_notifier.anonymizer_step(
          "🔐 Anonymisation des données (#{@parallel_connections} connexions parallèles)"
        )

        start_time = Time.zone.now

        work_queues = { connection_1: ["users"], connection_2: ["phone_numbers"], connection_3: ["payment_methods"] }

        @logger.info "[DatabaseAnonymizerService] Work queues configured:"
        work_queues.each { |connection_id, tables| @logger.info "  - #{connection_id}: #{tables.join(', ')}" }

        threads =
          work_queues.map do |connection_id, tables|
            Thread.new do
              @logger.info(
                "[DatabaseAnonymizerService][#{connection_id}] Starting thread for tables: #{tables.join(', ')}"
              )
              connection = establish_connection
              @logger.info "[DatabaseAnonymizerService][#{connection_id}] Database connection established"

              tables.each do |table|
                @logger.info "[DatabaseAnonymizerService][#{connection_id}] Processing table: #{table}"
                anonymize_table(connection, table)
              end

              connection.close
              @logger.info "[DatabaseAnonymizerService][#{connection_id}] Connection closed"
            end
          end

        @logger.info "[DatabaseAnonymizerService] Waiting for all threads to complete..."
        threads.each(&:join)

        duration = Time.zone.now - start_time
        @logger.info "[DatabaseAnonymizerService] ✅ Parallel anonymization completed in #{duration.round(2)}s"
        @slack_notifier.anonymizer_step("✅ Anonymisation terminée (#{duration.round(2)}s)")
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
        rows_affected = 0

        case table
        when "users"
          # Optimized single UPDATE for users
          @logger.info "[DatabaseAnonymizerService] Anonymizing users table (email, names, personal data)..."
          result = connection.exec(<<~SQL.squish)
            UPDATE users
            SET
              email = SUBSTRING(encode(digest(email::bytea, 'sha256'), 'hex'), 1, 8) || '@demo.yespark.fr',
              email_md5 = MD5(email),
              first_name = 'Demo',
              last_name = 'User' || id,
              full_name = first_name || ' ' || last_name,
              credit_card_last_4 = '0000',
              iban_last4 = '0000',
              stripe_customer_id = NULL,
              address_line1 = '8 rue du sentier',
              address_line2 = NULL,
              city = 'Paris',
              postal_code = '75002',
              birth_date = NULL,
              birth_place = NULL,
              google_token = NULL,
              facebook_token = NULL,
              apple_id = NULL,
              billing_extra = NULL,
              zendesk_user_id = NULL
            WHERE anonymized_at IS NULL
          SQL
          rows_affected = result.cmd_tuples
          @logger.info "[DatabaseAnonymizerService] Users table: #{rows_affected} rows anonymized"
        when "phone_numbers"
          @logger.info "[DatabaseAnonymizerService] Anonymizing phone_numbers table..."
          result = connection.exec(<<~SQL.squish)
            UPDATE phone_numbers
            SET number = '060' || LPAD(COALESCE(user_id::text, id::text), 7, '0')
          SQL
          rows_affected = result.cmd_tuples
          @logger.info "[DatabaseAnonymizerService] Phone numbers table: #{rows_affected} rows anonymized"
        when "payment_methods"
          @logger.info "[DatabaseAnonymizerService] Anonymizing payment_methods table..."
          result = connection.exec(<<~SQL.squish)
            UPDATE payment_methods
            SET card_last4 = '0000'
          SQL
          rows_affected = result.cmd_tuples
          @logger.info "[DatabaseAnonymizerService] Payment methods table: #{rows_affected} rows anonymized"
        else
          @logger.warn "[DatabaseAnonymizerService] Unknown table: #{table} - skipping"
        end

        duration = (Time.zone.now - start_time).round(2)
        @logger.info "[DatabaseAnonymizerService] ✓ Anonymized #{table} - #{rows_affected} rows in #{duration}s"

        # Translate table names for Slack notifications
        table_name_fr =
          case table
          when "users"
            "utilisateurs"
          when "phone_numbers"
            "téléphones"
          when "payment_methods"
            "moyens de paiement"
          else
            table
          end

        @slack_notifier.anonymizer_step("✓ #{table_name_fr.capitalize}: #{rows_affected} lignes anonymisées")
      rescue PG::Error => e
        @logger.error "[DatabaseAnonymizerService] Failed to anonymize #{table}: #{e.message}"
        @slack_notifier.anonymizer_error("Échec anonymisation #{table}")
        raise
      end
    end
  end
end
