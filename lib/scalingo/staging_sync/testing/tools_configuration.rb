# frozen_string_literal: true

module Scalingo
  module StagingSync
    # Module containing tool configuration definitions
    module ToolsConfiguration
      TOOLS_CONFIG = {
        "Scalingo CLI" => {
          command: "which scalingo",
          version_command: "scalingo version",
          required: true
        },
        "pg_restore" => {
          command: "which pg_restore",
          version_command: "pg_restore --version",
          required: true
        },
        "psql" => {
          command: "which psql",
          version_command: "psql --version",
          required: false
        },
        "tar" => {
          command: "which tar",
          version_command: "tar --version | head -1",
          required: true
        }
      }.freeze

      def tools_config
        TOOLS_CONFIG
      end
    end
  end
end
