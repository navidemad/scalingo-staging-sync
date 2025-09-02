# frozen_string_literal: true

require_relative "lib/scalingo/database/cloner/version"

Gem::Specification.new do |spec|
  spec.name = "scalingo-database-cloner"
  spec.version = Scalingo::Database::Cloner::VERSION
  spec.authors = ["Navid EMAD"]
  spec.email = ["navid.emad@yespark.fr"]

  spec.summary = "Scalingo database cloner with anonymization for staging environments"
  spec.description = "Clone and anonymize Scalingo production databases for safe use in staging/demo environments"
  spec.homepage = "https://github.com/navidemad/scalingo-database-cloner"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1"

  spec.metadata = {
    "bug_tracker_uri" => "https://github.com/navidemad/scalingo-database-cloner/issues",
    "changelog_uri" => "https://github.com/navidemad/scalingo-database-cloner/releases",
    "source_code_uri" => "https://github.com/navidemad/scalingo-database-cloner",
    "homepage_uri" => spec.homepage,
    "rubygems_mfa_required" => "true"
  }

  # Specify which files should be added to the gem when it is released.
  spec.files = Dir.glob(%w[LICENSE.txt README.md lib/**/*]).reject do |f|
    File.directory?(f)
  end
  spec.require_paths = ["lib"]

  # Runtime dependencies
  spec.add_dependency "pg"
  spec.add_dependency "scalingo"
end
