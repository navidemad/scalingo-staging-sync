# frozen_string_literal: true

require "test_helper"

module Scalingo
  module StagingSync
    class VersionTest < Minitest::Test
      def test_that_it_has_a_version_number
        refute_nil ::Scalingo::StagingSync::VERSION
      end
    end
  end
end
