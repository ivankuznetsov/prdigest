# frozen_string_literal: true

require "octokit"
require "set"
require "time"

module Prdigest
  class GitHub
    SEARCH_CAP = 1_000
    MAX_ATTEMPTS = 3

    def initialize(token:, client: nil, sleeper: ->(seconds) { sleep(seconds) }, now: -> { Time.now.to_i })
      @token = token.to_s
      @client = client || default_client
      @sleeper = sleeper
      @now = now
    end

    def fetch(date:, window:, repositories:, line_stats: false)
      pulls = repositories.flat_map do |repository|
        fetch_repository(repository, date, window, line_stats)
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

    def fetch_repository(repository, date, window, line_stats)
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

      mapped = items.map { |item| map_item(item, repository, date, window) }
      return mapped unless line_stats

      mapped.map do |pull|
        detail = request(repository, date) { @client.pull_request(repository, pull.number) }
        PullRequest.new(
          **pull.to_h,
          additions: Integer(field(detail, :additions)),
          deletions: Integer(field(detail, :deletions)),
          commits: Integer(field(detail, :commits))
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
