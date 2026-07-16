# frozen_string_literal: true

require_relative "lib/prdigest/version"

Gem::Specification.new do |spec|
  spec.name          = "prdigest"
  spec.version       = Prdigest::VERSION
  spec.authors       = ["Ivan Kuznetsov"]
  spec.email         = ["ivan@ikuznetsov.com"]

  spec.summary       = "Standalone multi-repo daily merged-PR digests for Telegram"
  spec.description   = "Config-driven GitHub merged-PR digests with Telegram delivery. " \
                       "Hive-independent: repo list + GitHub token + chat allowlist."
  spec.homepage      = "https://github.com/ivankuznetsov/prdigest"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      f.start_with?("test/", ".git", "bin/prdigest") || f == "Gemfile.lock"
    end
  end
  spec.bindir        = "exe"
  spec.executables   = ["prdigest"]
  spec.require_paths = ["lib"]

  spec.add_dependency "thor", "~> 1.3"
  spec.add_dependency "octokit", "~> 9.0"
  spec.add_dependency "faraday-retry", "~> 2.2"
  spec.add_dependency "tzinfo", "~> 2.0"

  spec.add_development_dependency "minitest", "~> 5.25"
  spec.add_development_dependency "rake", "~> 13.0"
end
