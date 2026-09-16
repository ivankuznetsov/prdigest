# frozen_string_literal: true

require "octokit"
require "set"
require "time"

module Prdigest
  class GitHub
    SEARCH_CAP = 1_000
    MAX_ATTEMPTS = 3
    MAX_DESCRIPTION_CHARS = 4_000
    MAX_PATCH_FILES = 20
    MAX_PATCH_CHARS = 6_000
    MAX_PATCH_SCAN_FILES = 100

    def initialize(token:, client: nil, sleeper: ->(seconds) { sleep(seconds) }, now: -> { Time.now.to_i })
      @token = token.to_s
      @client = client || default_client
      @sleeper = sleeper
      @now = now
    end

    def fetch(date:, window:, repositories:, line_stats: false, include_evidence: true)
      unless repositories.empty? || window.zero_length?
        repositories = Config.normalize_repos(repositories.map do |repository|
          response = request(repository, date) { @client.repository(repository) }
          field(response, :full_name)
        end)
      end
      pulls = repositories.flat_map do |repository|
        fetch_repository(repository, date, window, line_stats, include_evidence)
      end
      DayDigest.build(date: date, repository_order: repositories, pulls: pulls, line_stats: line_stats)
    end

    def inspect
      "#<#{self.class} token=[REDACTED]>"
    end

    alias to_s inspect

    private

    def default_client
      middleware = Octokit::Default::MIDDLEWARE.dup
      middleware.handlers.reject! { |handler| retry_middleware?(handler.klass) }
      Octokit::Client.new(
        access_token: @token,
        middleware: middleware,
        connection_options: { request: { open_timeout: 10, timeout: 30, write_timeout: 30 } }
      )
    end

    def retry_middleware?(middleware)
      %w[Faraday::Request::Retry Faraday::Retry::Middleware].include?(middleware.name)
    end

    def fetch_repository(repository, date, window, line_stats, include_evidence)
      return [] if window.zero_length?

      query = build_query(repository, window)
      page = 1
      items = []
      seen_numbers = Set.new
      total = nil
      loop do
        response = request(repository, date) { @client.search_issues(query, per_page: 100, page: page) }
        incomplete = field(response, :incomplete_results)
        fail_fetch!(repository, date, "incomplete search results") if incomplete
        response_total = Integer(field(response, :total_count))
        fail_fetch!(repository, date, "search result cap exceeded") if response_total > SEARCH_CAP
        total ||= response_total
        fail_fetch!(repository, date, "search total changed during pagination") unless total == response_total

        page_items = Array(field(response, :items))
        page_items.each do |item|
          number = Integer(field(item, :number))
          fail_fetch!(repository, date, "pagination repeated a pull request") unless seen_numbers.add?(number)
        end
        items.concat(page_items)
        fail_fetch!(repository, date, "pagination exceeded total") if items.length > total
        break if items.length == total
        fail_fetch!(repository, date, "pagination stopped before total") if page_items.empty?
        page += 1
      end

      return items.map { |item| map_item(item, repository, date, window) } unless include_evidence || line_stats

      items.map do |item|
        pull = map_item(item, repository, date, window)
        detail = request(repository, date) { @client.pull_request(repository, pull.number) }
        description, description_truncated = include_evidence ?
          bounded_text(optional_field(detail, :body), MAX_DESCRIPTION_CHARS) : ["", false]
        patches, patches_omitted = include_evidence ?
          fetch_patches(repository, pull.number, detail, date) : [[], 0]
        PullRequest.new(
          **pull.to_h,
          additions: line_stats ? Integer(field(detail, :additions)) : nil,
          deletions: line_stats ? Integer(field(detail, :deletions)) : nil,
          commits: line_stats ? Integer(field(detail, :commits)) : nil,
          description: description,
          description_truncated: description_truncated,
          patches: patches,
          patches_omitted: patches_omitted
        )
      end
    rescue FetchError
      raise
    rescue StandardError => e
      fail_fetch!(repository, date, "malformed GitHub response (#{e.class})")
    end

    def build_query(repository, window)
      finish = window.end_time - 1
      "repo:#{repository} is:pr is:merged merged:#{timestamp(window.start_time)}..#{timestamp(finish)}"
    end

    def timestamp(time)
      time.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
    end

    def map_item(item, repository, date, window)
      actual_repository = repository_name(item)
      merged_at = parse_time(field(field(item, :pull_request), :merged_at))
      unless actual_repository.casecmp?(repository) && window.cover?(merged_at)
        fail_fetch!(repository, date, "result outside requested repository or UTC window")
      end

      PullRequest.new(
        repository: repository,
        number: Integer(field(item, :number)),
        title: field(item, :title),
        url: field(item, :html_url),
        author: field(field(item, :user), :login),
        merged_at: merged_at
      )
    end

    def fetch_patches(repository, number, detail, date)
      files = Array(request(repository, date) {
        @client.pull_request_files(repository, number, per_page: MAX_PATCH_SCAN_FILES)
      })
      included = files.sort_by { |file| [patch_priority(field(file, :filename)), field(file, :filename).to_s] }
                      .first(MAX_PATCH_FILES).map do |file|
        source_patch = optional_field(file, :patch)
        patch, truncated = bounded_text(source_patch, MAX_PATCH_CHARS)
        {
          path: field(file, :filename).to_s,
          patch: patch,
          truncated: truncated,
          omitted: source_patch.nil?
        }
      end
      changed_files = Integer(field(detail, :changed_files))
      [included, [changed_files - included.length, 0].max]
    end

    def patch_priority(path)
      name = path.to_s.downcase
      return 2 if name.end_with?(".lock") || %w[gemfile.lock package-lock.json yarn.lock pnpm-lock.yaml].include?(name) ||
                  name.start_with?("vendor/", "dist/", "coverage/", "tmp/") || name.end_with?(".min.js", ".map")

      0
    end

    def bounded_text(value, limit)
      text = value.to_s
      return [text, false] if text.length <= limit

      [text[0, limit], true]
    end

    def parse_time(value)
      return value.utc if value.is_a?(Time)

      Time.iso8601(value.to_s).utc
    end

    def repository_name(item)
      repository = optional_field(item, :repository)
      full_name = optional_field(repository, :full_name) if repository
      return full_name.to_s unless full_name.to_s.empty?

      url = field(item, :repository_url).to_s
      match = url.match(%r{/repos/([^/]+/[^/]+)\z})
      raise KeyError, "repository identity missing" unless match
      match[1]
    end

    def field(object, key)
      value = optional_field(object, key)
      raise KeyError, key if value.nil?
      value
    end

    def optional_field(object, key)
      if object.respond_to?(:key?)
        return object[key] if object.key?(key)
        return object[key.to_s] if object.key?(key.to_s)
      end
      return object.public_send(key) if object.respond_to?(key)
    end

    def request(repository, date)
      attempts = 0
      begin
        attempts += 1
        yield
      rescue StandardError => e
        unless transient?(e) && attempts < MAX_ATTEMPTS
          fail_fetch!(repository, date, error_kind(e))
        end
        delay = retry_delay(e) || attempts
        fail_fetch!(repository, date, "retry delay exceeds 60 seconds") if delay > 60
        @sleeper.call(delay)
        retry
      end
    end

    def transient?(error)
      error.is_a?(Octokit::ServerError) ||
        rate_limited?(error) ||
        (defined?(Faraday::ConnectionFailed) && error.is_a?(Faraday::ConnectionFailed)) ||
        (defined?(Faraday::TimeoutError) && error.is_a?(Faraday::TimeoutError))
    end

    def rate_limited?(error)
      error.is_a?(Octokit::TooManyRequests) ||
        (error.respond_to?(:response_status) && Integer(error.response_status, exception: false) == 429)
    end

    def retry_delay(error)
      headers = error.respond_to?(:response_headers) ? error.response_headers : nil
      retry_after = Integer(response_header(headers, "retry-after"), exception: false)
      return retry_after if retry_after

      reset_at = Integer(response_header(headers, "x-ratelimit-reset"), exception: false)
      [reset_at - Integer(@now.call), 0].max if reset_at
    rescue StandardError
      nil
    end

    def response_header(headers, name)
      return unless headers

      Faraday::Utils::Headers.from(headers)[name]
    end

    def error_kind(error)
      transient?(error) ? "GitHub request retries exhausted" : "GitHub request refused"
    end

    def fail_fetch!(repository, date, reason)
      raise FetchError.new("GitHub fetch failed for #{repository} on #{date}: #{reason}", kind: "github")
    end
  end
end
