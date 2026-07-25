# frozen_string_literal: true

# Loaded with RUBYOPT by package/container smokes. It replaces the Octokit
# search and pull-detail reads, then refuses every lower-level HTTP request.
require "octokit"
require "net/http"
require "time"

class Octokit::Client
  def search_issues(query, _options = {})
    return { total_count: 0, incomplete_results: false, items: [] } if ENV["PRDIGEST_SMOKE_EMPTY"] == "1"

    repository = query[/\brepo:([^ ]+)/, 1]
    window = query[/\bmerged:([^ ]+)/, 1]
    raise "offline smoke query omitted repository" unless repository
    raise "offline smoke query omitted merge window" unless window

    merged_at = Time.iso8601(window.split("..", 2).fetch(0))

    {
      total_count: 1,
      incomplete_results: false,
      items: [{
        number: 1,
        title: "Synthetic packaged Time result",
        html_url: "https://github.com/#{repository}/pull/1",
        user: { login: "offline-smoke" },
        repository_url: "https://api.github.com/repos/#{repository}",
        pull_request: { merged_at: merged_at }
      }]
    }
  end

  def pull_request(_repository, _number)
    { additions: 3, deletions: 1, commits: 1 }
  end
end

class Net::HTTP
  def request(*)
    raise "offline smoke attempted external HTTP"
  end
end
