# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module ScalingoStagingSync
  module Integrations
    class SlackWebhookClient
      def initialize(webhook_url, logger: Rails.logger)
        @webhook_url = webhook_url
        @logger = logger
      end

      def post_message(text, options={})
        return false if @webhook_url.blank?

        payload = build_payload(text, options)
        send_webhook(payload)
      end

      private

      def build_payload(text, options)
        payload = { text: text }
        payload[:channel] = options[:channel] if options[:channel]
        payload[:username] = options[:username] if options[:username]
        payload[:icon_emoji] = options[:icon_emoji] if options[:icon_emoji]
        payload
      end

      def send_webhook(payload)
        response = execute_http_request(payload)
        handle_response(response)
      rescue StandardError => e
        @logger.error "[SlackWebhookClient] Error sending Slack notification: #{e.message}"
        false
      end

      def execute_http_request(payload)
        uri = URI.parse(@webhook_url)
        http = create_http_client(uri)
        request = build_request(uri, payload)
        http.request(request)
      end

      def create_http_client(uri)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.read_timeout = 10
        http.open_timeout = 10
        http
      end

      def build_request(uri, payload)
        request = Net::HTTP::Post.new(uri.request_uri)
        request["Content-Type"] = "application/json"
        request.body = payload.to_json
        request
      end

      def handle_response(response)
        if response.code.to_i == 200
          @logger.debug "[SlackWebhookClient] Message sent successfully"
          true
        else
          @logger.error "[SlackWebhookClient] Failed to send message: #{response.code} - #{response.body}"
          false
        end
      end
    end
  end
end
