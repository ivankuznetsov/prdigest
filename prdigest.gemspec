# frozen_string_literal: true

require_relative "lib/prdigest/version"

Gem::Specification.new do |spec|
  spec.name          = "prdigest"
  spec.version       = Prdigest::VERSION
  spec.authors       = ["Ivan Kuznetsov"]
  spec.email         = ["ivan@ikuznetsov.com"]

  spec.summary       = "Deterministic multi-repo merged-PR facts and digests"
  spec.description   = "Config-driven GitHub merged-PR facts with deterministic Telegram delivery " \
                       "and optional OpenAI-compatible prose. Hive-independent and secret-safe."
  spec.homepage      = "https://github.com/ivankuznetsov/prdigest"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "#{spec.homepage}/tree/main"
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.chdir(__dir__) do
    patterns = [
      "lib/**/*.rb", "exe/prdigest", "configs/config.example.yml",
      "scripts/systemd/*", "README.md", "SECURITY.md", "CHANGELOG.md", "LICENSE"
    ]
    patterns.flat_map { |pattern| Dir.glob(pattern) }.select { |path| File.file?(path) }.uniq.sort
  end
  spec.bindir        = "exe"
  spec.executables   = ["prdigest"]
  spec.require_paths = ["lib"]

  spec.add_dependency "thor", "~> 1.3"
  spec.add_dependency "octokit", "~> 9.0"
  spec.add_dependency "faraday-retry", "~> 2.2"
  spec.add_dependency "tzinfo", "~> 2.0"
  spec.add_dependency "erb", ">= 4.0", "< 7.0"

  spec.add_development_dependency "minitest", "~> 5.25"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "webmock", "~> 3.25"
end
