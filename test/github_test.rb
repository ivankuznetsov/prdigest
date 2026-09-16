# frozen_string_literal: true

require_relative "test_helper"

class GithubTest < Minitest::Test
  Response = Struct.new(:total_count, :incomplete_results, :items, keyword_init: true)

  class FakeClient
    attr_reader :searches, :details, :files

    def initialize(search_responses:, detail_responses: [], file_responses: [])
      @search_responses = search_responses.dup
      @detail_responses = detail_responses.dup
      @searches = []
      @details = []
      @file_responses = file_responses.dup
      @files = []
    end

    def repository(name)
      { full_name: name }
    end

    def search_issues(query, options)
      @searches << [query, options]
      value = @search_responses.shift
      raise value if value.is_a?(Exception)
      value
    end

    def pull_request(repo, number)
      @details << [repo, number]
      value = @detail_responses.shift
      raise value if value.is_a?(Exception)
      value || { body: "", changed_files: 0, additions: 0, deletions: 0, commits: 0 }
    end

    def pull_request_files(repo, number, options)
      @files << [repo, number, options]
      value = @file_responses.shift
      raise value if value.is_a?(Exception)
      value || []
    end
  end

  def setup
    stub_request(:get, "https://api.github.com/repos/o/r").to_return(
      headers: { "Content-Type" => "application/json" }, body: JSON.generate(full_name: "o/r")
    )
  end

  def test_resolves_renamed_repositories_before_search_and_deduplicates_aliases
    response = Response.new(total_count: 1, incomplete_results: false, items: [item(1, repo: "o/new")])
    client = FakeClient.new(search_responses: [response])
    client.define_singleton_method(:repository) { |_| { full_name: "o/new" } }
    digest = github(client).fetch(date: Date.new(2026, 1, 15), window: tokyo_window,
                                 repositories: ["o/old", "o/new"])
    assert_equal ["o/new"], digest.repositories.map(&:name)
    assert_equal 1, digest.total_prs
    assert_equal 1, client.searches.length
    assert_match(/repo:o\/new /, client.searches.first.first)
    assert_equal [["o/new", 1]], client.details
  end

  def test_builds_half_open_query_and_follows_pages
    first = Response.new(total_count: 2, incomplete_results: false, items: [item(2, "2026-01-15T10:00:00Z")])
    second = Response.new(total_count: 2, incomplete_results: false, items: [item(1, "2026-01-14T15:00:00Z")])
    client = FakeClient.new(
      search_responses: [first, second],
      detail_responses: [detail(body: "Adds the API", changed_files: 1), detail(body: "Fixes output", changed_files: 0)],
      file_responses: [[file("lib/api.rb", "puts :api")], []]
    )
    digest = github(client).fetch(date: Date.new(2026, 1, 15), window: tokyo_window, repositories: ["o/r"], line_stats: false)

    expected = "repo:o/r is:pr is:merged merged:2026-01-14T15:00:00Z..2026-01-15T14:59:59Z"
    assert_equal expected, client.searches.first.first
    assert_equal [1, 2], client.searches.map { |call| call.last[:page] }
    assert_equal [1, 2], digest.repositories.first.pull_requests.map(&:number)
    assert_equal [["o/r", 2], ["o/r", 1]], client.details
    assert_equal "Fixes output", digest.repositories.first.pull_requests.first.description
    assert_equal "lib/api.rb", digest.repositories.first.pull_requests.last.patches.first.fetch(:path)
  end

  def test_rejects_repeated_items_during_pagination
    first = Response.new(total_count: 2, incomplete_results: false, items: [item(1)])
    second = Response.new(total_count: 2, incomplete_results: false, items: [item(1)])
    client = FakeClient.new(search_responses: [first, second])

    error = assert_raises(Prdigest::FetchError) do
      github(client).fetch(
        date: Date.new(2026, 1, 15), window: tokyo_window, repositories: ["o/r"], line_stats: false
      )
    end

    assert_match(/pagination repeated a pull request/, error.message)
    assert_equal 2, client.searches.length
  end

  def test_accepts_false_and_zero_fields_from_json_hashes
    response = JSON.parse('{"total_count":0,"incomplete_results":false,"items":[]}')
    digest = github(FakeClient.new(search_responses: [response])).fetch(
      date: Date.new(2026, 1, 15), window: tokyo_window, repositories: ["o/r"], line_stats: false
    )
    assert_equal 0, digest.total_prs
  end

  def test_accepts_octokit_time_values_for_merged_at
    merged_at = Time.iso8601("2026-01-15T01:00:00Z")
    response = Response.new(total_count: 1, incomplete_results: false, items: [item(1, merged_at)])

    digest = github(FakeClient.new(search_responses: [response])).fetch(
      date: Date.new(2026, 1, 15), window: tokyo_window, repositories: ["o/r"], line_stats: false
    )

    assert_equal merged_at, digest.repositories.first.pull_requests.first.merged_at
  end

  def test_rejects_incomplete_over_cap_wrong_repo_and_outside_window
    invalid = [
      Response.new(total_count: 1, incomplete_results: true, items: []),
      Response.new(total_count: 1001, incomplete_results: false, items: []),
      Response.new(total_count: 1, incomplete_results: false, items: [item(1, "2026-01-15T00:00:00Z", repo: "x/y")]),
      Response.new(total_count: 1, incomplete_results: false, items: [item(1, "2026-01-15T15:00:00Z")])
    ]
    invalid.each do |response|
      error = assert_raises(Prdigest::FetchError) do
        github(FakeClient.new(search_responses: [response])).fetch(
          date: Date.new(2026, 1, 15), window: tokyo_window, repositories: ["o/r"], line_stats: false
        )
      end
      assert_match(/o\/r.*2026-01-15/, error.message)
    end
  end

  def test_enriches_every_pull_or_fails_whole_day
    response = Response.new(total_count: 2, incomplete_results: false, items: [item(1), item(2)])
    details = [detail(additions: 3, deletions: 1, commits: 2), detail(additions: 4, deletions: 2, commits: 1)]
    digest = github(FakeClient.new(search_responses: [response], detail_responses: details)).fetch(
      date: Date.new(2026, 1, 15), window: tokyo_window, repositories: ["o/r"], line_stats: true
    )
    assert_equal [7, 3, 3], [digest.total_additions, digest.total_deletions, digest.total_commits]

    client = FakeClient.new(
      search_responses: [response],
      detail_responses: [details.first, *Array.new(3) { Octokit::ServerError.new }]
    )
    assert_raises(Prdigest::FetchError) do
      github(client).fetch(date: Date.new(2026, 1, 15), window: tokyo_window, repositories: ["o/r"], line_stats: true)
    end
  end

  def test_bounds_descriptions_and_patches_with_explicit_metadata
    response = Response.new(total_count: 1, incomplete_results: false, items: [item(1)])
    long_body = "d" * (Prdigest::GitHub::MAX_DESCRIPTION_CHARS + 1)
    long_patch = "p" * (Prdigest::GitHub::MAX_PATCH_CHARS + 1)
    files = Array.new(Prdigest::GitHub::MAX_PATCH_FILES + 1) { |index| file("lib/#{index}.rb", long_patch) }
    pull = github(FakeClient.new(
      search_responses: [response],
      detail_responses: [detail(body: long_body, changed_files: files.length)],
      file_responses: [files]
    )).fetch(date: Date.new(2026, 1, 15), window: tokyo_window, repositories: ["o/r"], line_stats: false)
      .repositories.first.pull_requests.first

    assert_equal Prdigest::GitHub::MAX_DESCRIPTION_CHARS, pull.description.length
    assert_equal true, pull.description_truncated
    assert_equal Prdigest::GitHub::MAX_PATCH_FILES, pull.patches.length
    assert_equal 1, pull.patches_omitted
    assert_equal Prdigest::GitHub::MAX_PATCH_CHARS, pull.patches.first.fetch(:patch).length
    assert_equal true, pull.patches.first.fetch(:truncated)
  end

  def test_marks_a_file_without_a_text_patch_as_omitted
    response = Response.new(total_count: 1, incomplete_results: false, items: [item(1)])
    pull = github(FakeClient.new(
      search_responses: [response],
      detail_responses: [detail(changed_files: 1)],
      file_responses: [[{ filename: "assets/logo.png" }]]
    )).fetch(date: Date.new(2026, 1, 15), window: tokyo_window, repositories: ["o/r"], line_stats: false)
      .repositories.first.pull_requests.first

    assert_equal "", pull.patches.first.fetch(:patch)
    assert_equal true, pull.patches.first.fetch(:omitted)
    assert_equal false, pull.patches.first.fetch(:truncated)
  end

  def test_accepts_nil_bodies_and_prioritizes_source_patches_over_lockfiles
    response = Response.new(total_count: 1, incomplete_results: false, items: [item(1)])
    files = [file("Gemfile.lock", "lock"), file("package-lock.json", "lock"), file("lib/feature.rb", "def feature; end")]
    pull = github(FakeClient.new(
      search_responses: [response],
      detail_responses: [detail(body: nil, changed_files: files.length)],
      file_responses: [files]
    )).fetch(date: Date.new(2026, 1, 15), window: tokyo_window, repositories: ["o/r"], line_stats: false)
      .repositories.first.pull_requests.first

    assert_equal "", pull.description
    assert_equal "lib/feature.rb", pull.patches.first.fetch(:path)
  end

  def test_collects_line_statistics_when_evidence_is_disabled
    response = Response.new(total_count: 1, incomplete_results: false, items: [item(1)])
    client = FakeClient.new(search_responses: [response], detail_responses: [detail(additions: 3, deletions: 2, commits: 1)])
    pull = github(client).fetch(
      date: Date.new(2026, 1, 15), window: tokyo_window, repositories: ["o/r"],
      line_stats: true, include_evidence: false
    ).repositories.first.pull_requests.first

    assert_equal [3, 2, 1], [pull.additions, pull.deletions, pull.commits]
    assert_empty pull.patches
    assert_empty client.files
  end

  def test_retries_transient_failures_three_total_attempts
    sleeps = []
    response = Response.new(total_count: 0, incomplete_results: false, items: [])
    client = FakeClient.new(search_responses: [Octokit::ServerError.new, response])
    digest = github(client, sleeper: ->(seconds) { sleeps << seconds }).fetch(
      date: Date.new(2026, 1, 15), window: tokyo_window, repositories: ["o/r"], line_stats: false
    )
    assert_equal 0, digest.total_prs
    assert_equal [1], sleeps

    client = FakeClient.new(search_responses: Array.new(3) { Faraday::ConnectionFailed.new("token-secret") })
    error = assert_raises(Prdigest::FetchError) do
      github(client, token: "token-secret").fetch(
        date: Date.new(2026, 1, 15), window: tokyo_window, repositories: ["o/r"], line_stats: false
      )
    end
    refute_includes error.message, "token-secret"
    assert_equal 3, client.searches.length
  end

  def test_default_octokit_transport_is_bounded_to_three_http_attempts
    request = stub_request(:get, %r{\Ahttps://api\.github\.com/search/issues\?}).to_return(
      status: 500,
      headers: { "Content-Type" => "application/json" },
      body: JSON.generate(message: "synthetic server failure")
    )

    assert_raises(Prdigest::FetchError) do
      github.fetch(
        date: Date.new(2026, 1, 15), window: tokyo_window, repositories: ["o/r"], line_stats: false
      )
    end

    assert_requested request, times: 3
  end

  def test_retries_real_429_responses_using_retry_after
    sleeps = []
    stub_request(:get, %r{\Ahttps://api\.github\.com/search/issues\?}).to_return(
      {
        status: 429,
        headers: { "Content-Type" => "application/json", "Retry-After" => "2" },
        body: JSON.generate(message: "synthetic rate limit")
      },
      {
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: JSON.generate(total_count: 0, incomplete_results: false, items: [])
      }
    )

    digest = github(sleeper: ->(seconds) { sleeps << seconds }).fetch(
      date: Date.new(2026, 1, 15), window: tokyo_window, repositories: ["o/r"], line_stats: false
    )

    assert_equal 0, digest.total_prs
    assert_equal [2], sleeps
  end

  def test_uses_rate_limit_reset_when_retry_after_is_absent
    sleeps = []
    stub_request(:get, %r{\Ahttps://api\.github\.com/search/issues\?}).to_return(
      {
        status: 429,
        headers: { "Content-Type" => "application/json", "X-RateLimit-Reset" => "1045" },
        body: JSON.generate(message: "synthetic rate limit")
      },
      {
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: JSON.generate(total_count: 0, incomplete_results: false, items: [])
      }
    )

    digest = github(sleeper: ->(seconds) { sleeps << seconds }, now: -> { 1_000 }).fetch(
      date: Date.new(2026, 1, 15), window: tokyo_window, repositories: ["o/r"], line_stats: false
    )

    assert_equal 0, digest.total_prs
    assert_equal [45], sleeps
  end

  def test_inspection_redacts_token
    token = "synthetic-secret"
    client = github(FakeClient.new(search_responses: []), token: token)

    [client.inspect, client.to_s].each { |surface| refute_includes surface, token }
  end

  private

  def github(client = nil, sleeper: ->(*) {}, token: "synthetic-token", now: -> { Time.now.to_i })
    Prdigest::GitHub.new(token: token, client: client, sleeper: sleeper, now: now)
  end

  def tokyo_window
    Prdigest::Clock.new(timezone: "Asia/Tokyo").window(Date.new(2026, 1, 15))
  end

  def item(number, merged_at = "2026-01-15T01:00:00Z", repo: "o/r")
    {
      number: number,
      title: "Synthetic PR #{number}",
      html_url: "https://github.com/#{repo}/pull/#{number}",
      user: { login: "developer" },
      repository_url: "https://api.github.com/repos/#{repo}",
      pull_request: { merged_at: merged_at }
    }
  end

  def detail(body: "", changed_files: 0, additions: 0, deletions: 0, commits: 0)
    { body: body, changed_files: changed_files, additions: additions, deletions: deletions, commits: commits }
  end

  def file(filename, patch)
    { filename: filename, patch: patch }
  end
end
