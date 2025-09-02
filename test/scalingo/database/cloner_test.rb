# frozen_string_literal: true

require "test_helper"

module Scalingo
  module Database
    class ClonerTest < Minitest::Test
      def test_that_it_has_a_version_number
        refute_nil ::Scalingo::Database::Cloner::VERSION
      end
    end
  end
end
