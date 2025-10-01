# frozen_string_literal: true

require "open3"

module ScalingoStagingSync
  module Database
    # Module for TOC (Table of Contents) filtering for pg_restore
    module TocFilter
      def generate_filtered_toc(backup_file, exclude_tables)
        @logger.info "[DatabaseRestoreService] Generating filtered TOC (excluding #{exclude_tables.size} tables)..."
        @logger.info "[DatabaseRestoreService] Excluded tables: #{exclude_tables.join(', ')}"
        @slack_notifier.restore_step("📑 Préparation: #{exclude_tables.size} tables exclues")

        toc_output = generate_toc_listing(backup_file)
        filtered_lines = filter_toc_lines(toc_output, exclude_tables)
        save_toc_file(filtered_lines, toc_output.lines.size)
      end

      private

      def generate_toc_listing(backup_file)
        @logger.info "[DatabaseRestoreService] Running pg_restore -l to list backup contents..."
        toc_output, error, status = Open3.capture3("pg_restore", "-l", backup_file)

        unless status.success?
          @logger.error "[DatabaseRestoreService] Failed to generate TOC listing: #{error}"
          raise "Failed to generate TOC listing with pg_restore -l"
        end

        @logger.info "[DatabaseRestoreService] TOC listing completed: #{toc_output.lines.size} total entries"
        toc_output
      end

      def filter_toc_lines(toc_output, exclude_tables)
        toc_output.lines.reject do |line|
          should_exclude_line?(line, exclude_tables)
        end
      end

      def should_exclude_line?(line, exclude_tables)
        # Skip system schemas
        return true if system_schema?(line)

        # Skip excluded tables
        return true if excluded_table?(line, exclude_tables)

        false
      end

      def system_schema?(line)
        line.include?("pg_repack") || line.include?("heroku_ext") || line.include?("pg_catalog")
      end

      def excluded_table?(line, exclude_tables)
        return false unless exclude_tables.any? && line.include?("TABLE DATA")

        tables_regex = exclude_tables.join("|")
        line.match?(/TABLE DATA public\s+(?:#{tables_regex})\s/)
      end

      def save_toc_file(filtered_lines, original_count)
        toc_file = File.join(Dir.tmpdir, "filtered_#{Time.current.to_i}.toc")
        File.write(toc_file, filtered_lines.join)

        @logger.info "[DatabaseRestoreService] TOC file generated: #{toc_file}"
        @logger.info "[DatabaseRestoreService] TOC contains #{filtered_lines.size} entries " \
                     "(filtered from #{original_count})"
        toc_file
      end
    end
  end
end
