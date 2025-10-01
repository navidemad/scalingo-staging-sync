# frozen_string_literal: true

require "net/http"
require_relative "utilities"

module ScalingoStagingSync
  module Support
    # Handles file download operations with progress tracking
    class FileDownloader
      include Support::Utilities

      DEFAULT_TIMEOUT = 1200 # 20 minutes

      def initialize(logger: Rails.logger, timeout: DEFAULT_TIMEOUT)
        @logger = logger
        @timeout = timeout
      end

      def download(url, filename)
        uri = URI(url)
        bytes_downloaded = 0
        start_time = Time.current

        http = create_http_connection(uri)
        request = Net::HTTP::Get.new(uri)
        request["Accept"] = "application/octet-stream"

        download_with_progress(http, request, filename, bytes_downloaded)

        elapsed = (Time.current - start_time).round(2)
        log_download_completion(filename, bytes_downloaded, elapsed)
      rescue StandardError => e
        handle_download_error(e, url, filename)
      end

      private

      def create_http_connection(uri)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.read_timeout = @timeout
        http.open_timeout = 30
        http
      end

      def download_with_progress(http, request, filename, bytes_downloaded)
        File.open(filename, "wb") do |file|
          http.request(request) do |response|
            validate_response(response)
            total_size = response["content-length"].to_i if response["content-length"]

            response.read_body do |chunk|
              file.write(chunk)
              bytes_downloaded += chunk.size
              log_progress(bytes_downloaded, total_size, chunk.size) if total_size
            end
          end
        end
        bytes_downloaded
      end

      def validate_response(response)
        return if response.is_a?(Net::HTTPSuccess)

        raise Integrations::BackupService::DownloadError, "Download failed: #{response.code} - #{response.message}"
      end

      def log_progress(bytes_downloaded, total_size, chunk_size)
        # Log every 500MB
        return unless (bytes_downloaded % (500 * 1024 * 1024)) < chunk_size

        progress = (bytes_downloaded.to_f / total_size * 100).round(2)
        log_context(
          :info,
          "Download progress",
          progress: "#{progress}%",
          downloaded: format_bytes(bytes_downloaded),
          total: format_bytes(total_size)
        )
      end

      def log_download_completion(filename, bytes_downloaded, elapsed)
        log_context(
          :info,
          "Download completed",
          filename: filename,
          size: format_bytes(bytes_downloaded),
          elapsed: "#{elapsed}s"
        )
      end

      def handle_download_error(error, url, filename)
        log_context(:error, "Download failed", error: error.message, url: url)
        FileUtils.rm_f(filename) # Clean up partial download
        raise
      end
    end
  end
end
