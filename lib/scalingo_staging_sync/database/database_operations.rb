# frozen_string_literal: true

require "open3"

module ScalingoStagingSync
  module Database
    # Module for database operations (recreation, migrations, extensions)
    module DatabaseOperations
      def recreate_database
        @logger.info "[DatabaseRestoreService] Recreating database for clean restore..."
        @slack_notifier.restore_step("🗑️ Recréation de la base de données...")

        drop_database
        create_database

        @logger.info "[DatabaseRestoreService] ✓ Database recreated successfully"
        @slack_notifier.restore_step("✓ Base recréée et prête")
      end

      def drop_database
        @logger.info "[DatabaseRestoreService] Dropping existing database using Rails db:drop..."

        env = {
          "DATABASE_URL" => @database_url,
          "DISABLE_DATABASE_ENVIRONMENT_CHECK" => "1"
        }
        drop_result = system(env, "bin/rails", "db:drop", err: %i[child out])

        if drop_result
          @logger.info "[DatabaseRestoreService] Database dropped successfully"
        else
          @logger.warn "[DatabaseRestoreService] db:drop failed (database might not exist), continuing..."
        end
      end

      def create_database
        @logger.info "[DatabaseRestoreService] Creating fresh database using Rails db:create..."

        env = { "DATABASE_URL" => @database_url }
        create_result = system(env, "bin/rails", "db:create")

        unless create_result
          @logger.error "[DatabaseRestoreService] Failed to create database with db:create"
          @slack_notifier.restore_error("Échec création base de données")
          raise "Failed to create database"
        end

        @logger.info "[DatabaseRestoreService] Database created successfully"
      end

      def run_migrations
        @logger.info "[DatabaseRestoreService] Running database migrations..."
        @slack_notifier.restore_step("🔄 Exécution des migrations...")

        env = { "DATABASE_URL" => @database_url }
        result = system(env, "bin/rails", "db:migrate")

        if result
          @logger.info "[DatabaseRestoreService] ✓ Migrations completed successfully"
          @slack_notifier.restore_step("✓ Migrations terminées")
        else
          @logger.error "[DatabaseRestoreService] Migration failed"
          @slack_notifier.restore_error("Échec des migrations")
          raise "Database migrations failed"
        end
      end

      def display_installed_extensions
        @logger.info "[DatabaseRestoreService] Checking installed PostgreSQL extensions..."

        extensions_query = <<~SQL.squish
          SELECT extname, extversion
          FROM pg_extension
          WHERE extname NOT IN ('plpgsql')
          ORDER BY extname;
        SQL

        output, _error, status = Open3.capture3("psql", @pg_url, "-t", "-c", extensions_query)

        return log_extension_query_failure unless status.success?

        extensions = output.strip.split("\n").map(&:strip).reject(&:empty?)
        log_extensions(extensions)
      end

      private

      def log_extension_query_failure
        @logger.warn "[DatabaseRestoreService] Failed to query installed extensions"
      end

      def log_extensions(extensions)
        if extensions.any?
          @logger.info "[DatabaseRestoreService] Installed extensions:"
          extensions.each { |ext| @logger.info "[DatabaseRestoreService]   - #{ext}" }
        else
          @logger.info "[DatabaseRestoreService] No additional extensions installed (only plpgsql)"
        end
      end
    end
  end
end
