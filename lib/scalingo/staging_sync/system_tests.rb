# frozen_string_literal: true

require_relative "tools_configuration"
require_relative "database_info_logger"

module Scalingo
  module StagingSync
    # Module for system tools and database connectivity testing
    module SystemTests
      include ToolsConfiguration
      include DatabaseInfoLogger

      def test_required_tools
        @logger.info "[StagingSyncTester] Testing required tools availability..."
        section_header("Required Tools")

        tools_config.each do |name, config|
          test_tool_availability(name, config)
        end
      end

      def test_database_connectivity
        @logger.info "[StagingSyncTester] Testing database connectivity..."
        section_header("Database Connectivity")

        database_url = ENV["DATABASE_URL"] || ENV.fetch("SCALINGO_POSTGRESQL_URL", nil)

        if database_url.blank?
          @logger.error "[StagingSyncTester] No database URL available for testing"
          raise "Cannot test - no database URL"
        end

        test_database_connection(database_url)
      end

      def test_permissions
        @logger.info "[StagingSyncTester] Testing file system permissions..."
        section_header("File System Permissions")

        test_temp_directory_permissions
        test_staging_seeds_file
      end

      private

      # Tools configuration is provided by ToolsConfiguration module

      def test_tool_availability(name, config)
        if system(config[:command], out: File::NULL, err: File::NULL)
          version = `#{config[:version_command]} 2>/dev/null`.strip.split("\n").first
          pass "#{name}: Available (#{version})"
          @logger.info "[StagingSyncTester] Tool available: #{name} - #{version}"
        elsif config[:required]
          @logger.error "[StagingSyncTester] Required tool missing: #{name}"
          raise "#{name}: Not found (REQUIRED)"
        else
          warn "#{name}: Not found (optional)"
          @logger.warn "[StagingSyncTester] Optional tool missing: #{name}"
        end
      end

      def test_database_connection(database_url)
        uri = URI.parse(database_url)
        connection = PG.connect(
          host: uri.host,
          port: uri.port || 5432,
          dbname: uri.path[1..],
          user: uri.user,
          password: uri.password,
          connect_timeout: 5
        )

        log_database_info(connection)
        connection.close
        @logger.info "[StagingSyncTester] Database connection test completed successfully"
      rescue PG::Error => e
        @logger.error "[StagingSyncTester] Database connection failed: #{e.message}"
        raise "Database connection failed: #{e.message}"
      rescue StandardError => e
        @logger.error "[StagingSyncTester] Unexpected error during database test: #{e.message}"
        raise "Unexpected error: #{e.message}"
      end

      # Database info logging methods are provided by DatabaseInfoLogger module

      def test_temp_directory_permissions
        temp_dir = Rails.root.join("tmp")
        if File.writable?(temp_dir)
          pass "Temp directory writable: #{temp_dir}"
          @logger.info "[StagingSyncTester] Temp directory is writable: #{temp_dir}"
        else
          @logger.error "[StagingSyncTester] Temp directory is not writable: #{temp_dir}"
          raise "Temp directory not writable: #{temp_dir}"
        end
      end

      def test_staging_seeds_file
        seeds_file = Rails.root.join("db/seeds/staging.rb")
        if File.exist?(seeds_file)
          pass "Staging seeds file exists"
          info "  Path: #{seeds_file}"
          info "  Size: #{(File.size(seeds_file) / 1024.0).round(2)} KB"
        else
          warn "Staging seeds file not found: #{seeds_file}"
        end
      end
    end
  end
end
