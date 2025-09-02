# frozen_string_literal: true

require "open3"

module Scalingo
  module StagingSync
    class DatabaseRestoreService
      def initialize(database_url, logger: Rails.logger)
        # Store both versions: postgis:// for Rails, postgres:// for command-line tools
        @database_url = database_url.sub(/^postgres/, "postgis") # For Rails (handles PostGIS types)
        @pg_url = database_url.sub(/^postgis/, "postgres") # For psql, pg_restore, etc.
        @logger = logger
        @slack_notifier = Scalingo::StagingSync::SlackNotificationService.new(logger: logger)
      end

      def restore!(backup_file, toc_file: nil, exclude_tables: [])
        @logger.info "[DatabaseRestoreService] Starting database restore process..."
        @slack_notifier.restore_step("💾 Restauration de la base de données...")

        @logger.info "[DatabaseRestoreService] Backup file: #{backup_file}"
        @logger.info "[DatabaseRestoreService] Excluded tables: #{exclude_tables.join(', ')}" if exclude_tables.any?

        # Generate TOC if needed
        toc_file = generate_filtered_toc(backup_file, exclude_tables) if exclude_tables.any? && toc_file.nil?

        # Perform the restore
        @logger.info "[DatabaseRestoreService] Checking available restore methods..."
        if pg_restore_available?
          @logger.info "[DatabaseRestoreService] Using pg_restore for database restoration"
          restore_with_pg_restore(backup_file, toc_file)
        else
          @logger.warn "[DatabaseRestoreService] pg_restore not available, falling back to psql"
          restore_with_psql(backup_file)
        end

        # Run migrations to ensure schema is up to date
        @logger.info "[DatabaseRestoreService] Running database migrations..."
        run_migrations

        # Display installed extensions
        @logger.info "[DatabaseRestoreService] Checking installed PostgreSQL extensions..."
        display_installed_extensions

        @logger.info "[DatabaseRestoreService] ✅ Database restore completed successfully"
        @slack_notifier.restore_step("✅ Base de données restaurée avec succès")
      rescue StandardError => e
        @logger.error "[DatabaseRestoreService] Restore failed: #{e.message}"
        @logger.error "[DatabaseRestoreService] Backtrace: #{e.backtrace.first(5).join('\n')}"
        @slack_notifier.restore_error("Échec de la restauration")
        raise
      end

      private

      def generate_filtered_toc(backup_file, exclude_tables)
        @logger.info "[DatabaseRestoreService] Generating filtered TOC (excluding #{exclude_tables.size} tables)..."
        @logger.info "[DatabaseRestoreService] Excluded tables: #{exclude_tables.join(', ')}"
        @slack_notifier.restore_step("📑 Préparation: #{exclude_tables.size} tables exclues")

        @logger.info "[DatabaseRestoreService] Running pg_restore -l to list backup contents..."
        toc_output = `pg_restore -l "#{backup_file}"`
        @logger.info "[DatabaseRestoreService] TOC listing completed: #{toc_output.lines.size} total entries"

        filtered_lines =
          toc_output.lines.reject do |line|
            # Skip system schemas
            next true if line.include?("pg_repack") || line.include?("heroku_ext") || line.include?("pg_catalog")

            # Skip excluded tables
            if exclude_tables.any? && line.include?("TABLE DATA")
              tables_regex = exclude_tables.join("|")
              next true if line.match?(/TABLE DATA public\s+(?:#{tables_regex})\s/)
            end

            false
          end

        toc_file = File.join(Dir.tmpdir, "filtered_#{Time.now.to_i}.toc")
        File.write(toc_file, filtered_lines.join)

        @logger.info "[DatabaseRestoreService] TOC file generated: #{toc_file}"
        @logger.info "[DatabaseRestoreService] TOC contains #{filtered_lines.size} entries (filtered from #{toc_output.lines.size})"
        toc_file
      end

      def pg_restore_available?
        available = system("which pg_restore", out: File::NULL, err: File::NULL)
        @logger.debug "[DatabaseRestoreService] pg_restore availability: #{available}"
        available
      end

      def restore_with_pg_restore(backup_file, toc_file)
        @logger.info "[DatabaseRestoreService] Starting pg_restore (parallel mode, excluding pghero/heroku_ext schemas)..."
        @slack_notifier.restore_step("🔄 Restauration avec pg_restore")

        # Always drop and recreate the database for a clean restore
        recreate_database

        restore_cmd = build_pg_restore_command(backup_file, toc_file)
        @logger.info "[DatabaseRestoreService] Executing pg_restore command..."
        @logger.debug "[DatabaseRestoreService] Command: #{restore_cmd}"

        # Capture output and error for better debugging
        output, error, status = Open3.capture3(restore_cmd)
        @logger.debug "[DatabaseRestoreService] pg_restore output lines: #{output.lines.size}"

        unless status.success?
          @logger.error "[DatabaseRestoreService] pg_restore failed with exit code: #{status.exitstatus}"
          @logger.error "[DatabaseRestoreService] Error output: #{error}"
          @slack_notifier.restore_error("Échec pg_restore (code: #{status.exitstatus})")
          raise "Database restore failed with pg_restore"
        end

        @logger.info "[DatabaseRestoreService] ✓ pg_restore completed successfully"
        @slack_notifier.restore_step("✓ Données restaurées")
      end

      def restore_with_psql(backup_file)
        @logger.warn "[DatabaseRestoreService] pg_restore not found, using psql fallback..."
        @slack_notifier.restore_step("⚠️ Utilisation de psql (fallback)")

        restore_cmd = "psql \"#{@pg_url}\" < \"#{backup_file}\""
        @logger.info "[DatabaseRestoreService] Executing psql restore command..."

        unless system(restore_cmd)
          @logger.error "[DatabaseRestoreService] psql restore failed"
          @slack_notifier.restore_error("Échec restauration psql")
          raise "Database restore failed with psql"
        end

        @logger.info "[DatabaseRestoreService] ✓ psql restore completed"
      end

      def build_pg_restore_command(backup_file, toc_file)
        # Build pg_restore command with proper exclusions
        cmd_parts = [
          "pg_restore",
          "--verbose",
          "--no-owner",
          "--no-acl",
          "--no-privileges",
          "--no-subscriptions",
          "--no-security-labels",
          "--no-publications",
          "--no-comments",
          "--no-tablespaces",
          "--exclude-schema=pghero", # Exclude PgHero monitoring schema
          "--exclude-schema=heroku_ext", # Exclude Heroku extensions schema
          "--jobs=4" # Parallel restore for speed
        ]

        # Add TOC file if provided for additional filtering
        cmd_parts << "-L \"#{toc_file}\"" if toc_file

        # Add database URL and backup file
        cmd_parts << "-d \"#{@pg_url}\""
        cmd_parts << "\"#{backup_file}\""

        # Set color output for better debugging
        "PG_COLOR='always' #{cmd_parts.join(' ')}"
      end

      def recreate_database
        @logger.info "[DatabaseRestoreService] Recreating database for clean restore..."
        @slack_notifier.restore_step("🗑️ Recréation de la base de données...")

        # Use Rails db:drop and db:create for cleaner database management
        # This handles connection termination and proper database creation

        @logger.info "[DatabaseRestoreService] Dropping existing database using Rails db:drop..."

        # Run db:drop to properly drop the database
        drop_result =
          system("DATABASE_URL=\"#{@database_url}\" DISABLE_DATABASE_ENVIRONMENT_CHECK=\"1\" bin/rails db:drop 2>&1")

        if drop_result
          @logger.info "[DatabaseRestoreService] Database dropped successfully"
        else
          @logger.warn "[DatabaseRestoreService] db:drop failed (database might not exist), continuing..."
        end

        @logger.info "[DatabaseRestoreService] Creating fresh database using Rails db:create..."

        # Run db:create to create a fresh database with proper settings
        create_result = system("DATABASE_URL=\"#{@database_url}\" bin/rails db:create")

        unless create_result
          @logger.error "[DatabaseRestoreService] Failed to create database with db:create"
          @slack_notifier.restore_error("Échec création base de données")
          raise "Failed to create database"
        end

        @logger.info "[DatabaseRestoreService] Database created successfully"

        @logger.info "[DatabaseRestoreService] ✓ Database recreated successfully"
        @slack_notifier.restore_step("✓ Base recréée et prête")
      end

      def run_migrations
        @logger.info "[DatabaseRestoreService] Running database migrations..."
        @slack_notifier.restore_step("🔄 Exécution des migrations...")

        result = system("DATABASE_URL=\"#{@database_url}\" bin/rails db:migrate")

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

        output, _error, status = Open3.capture3("psql \"#{@pg_url}\" -t -c \"#{extensions_query}\" ")

        if status.success?
          extensions = output.strip.split("\n").map(&:strip).reject(&:empty?)

          if extensions.any?
            @logger.info "[DatabaseRestoreService] Installed extensions:"
            extensions.each { |ext| @logger.info "[DatabaseRestoreService]   - #{ext}" }
          else
            @logger.info "[DatabaseRestoreService] No additional extensions installed (only plpgsql)"
          end
        else
          @logger.warn "[DatabaseRestoreService] Failed to query installed extensions"
        end
      end
    end
  end
end
