# frozen_string_literal: true

# Loaded with RUBYOPT by package/container smokes. It replaces the only network
# read used by dry-run and then refuses every lower-level HTTP request.
require "octokit"
require "net/http"

class Octokit::Client
  def search_issues(_query, _options = {})
    { total_count: 0, incomplete_results: false, items: [] }
  end
end

class Net::HTTP
  def request(*)
    raise "offline smoke attempted external HTTP"
  end
end
