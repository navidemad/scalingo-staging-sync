# frozen_string_literal: true

module Scalingo
  module StagingSync
    # Module for archive extraction and file management operations
    module ArchiveHandler
      def extract_and_prepare_backup(archive)
        log_context(:info, "Starting archive extraction", archive: archive, size: format_bytes(File.size(archive)))
        @slack_notifier.backup_step("📦 Extraction de l'archive...")

        extract_archive(archive)
        dump_file = find_and_validate_dump_file
        standardized_path = standardize_dump_file(dump_file)
        cleanup_archive(archive)

        log_context(
          :info,
          "Backup preparation completed",
          path: standardized_path.to_s,
          size: format_bytes(File.size(standardized_path))
        )
        standardized_path
      end

      def extract_archive(archive)
        log_context(:info, "Running tar extraction command")
        success = system("tar -xzf \"#{archive}\"")
        raise BackupError, "Failed to extract archive: #{archive}" unless success

        log_context(:info, "Archive extraction completed successfully")
      end

      def find_and_validate_dump_file
        log_context(:info, "Searching for dump file in extracted contents")
        dump_file = find_dump_file
        raise BackupError, "No dump file found in archive" unless dump_file

        log_context(:info, "Found dump file", dump_file: dump_file, size: format_bytes(File.size(dump_file)))
        dump_file
      end

      def standardize_dump_file(dump_file)
        standardized_path = @temp_dir.join("production.dump")
        log_context(:info, "Standardizing dump filename", from: dump_file, to: standardized_path.to_s)
        FileUtils.mv(dump_file, standardized_path)
        standardized_path
      end

      def cleanup_archive(archive)
        log_context(:info, "Cleaning up archive file", archive: archive)
        FileUtils.rm_f(archive)
      end

      def find_latest_archive
        archives = Dir.glob("*.tar.gz")
        log_context(
          :debug,
          "Found archives in temp directory",
          count: archives.size,
          files: archives.take(3).join(", ")
        )
        archives.max_by { |f| File.mtime(f) }
      end

      def find_dump_file
        pgsql_files = Dir.glob("*.pgsql")
        dump_files = Dir.glob("*.dump")
        sql_files = Dir.glob("*.sql")

        log_context(
          :debug,
          "Searching for dump files",
          pgsql: pgsql_files.size,
          dump:  dump_files.size,
          sql:   sql_files.size
        )

        pgsql_files.first || dump_files.first || sql_files.first
      end
    end
  end
end
