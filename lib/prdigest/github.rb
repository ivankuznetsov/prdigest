# frozen_string_literal: true

require "octokit"
require "time"

module Prdigest
  class GitHub
    SEARCH_CAP = 1_000
    MAX_ATTEMPTS = 3

    def initialize(token:, client: nil, sleeper: ->(seconds) { sleep(seconds) })
      @token = token.to_s
      @client = client || Octokit::Client.new(
        access_token: @token,
        connection_options: { request: { open_timeout: 10, timeout: 30, write_timeout: 30 } }
      )
      @sleeper = sleeper
    end

    def fetch(date:, window:, repositories:, line_stats: false)
      pulls = repositories.flat_map do |repository|
        fetch_repository(repository, date, window, line_stats)
      end
      DayDigest.build(date: date, repository_order: repositories, pulls: pulls, line_stats: line_stats)
    end

    private

    def fetch_repository(repository, date, window, line_stats)
      return [] if window.zero_length?

      query = build_query(repository, window)
      page = 1
      items = []
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
        items.concat(page_items)
        break if items.length >= total
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
      merged_at = Time.iso8601(field(field(item, :pull_request), :merged_at).to_s).utc
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
      return object[key] || object[key.to_s] if object.respond_to?(:key?)
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
        (defined?(Octokit::TooManyRequests) && error.is_a?(Octokit::TooManyRequests)) ||
        (defined?(Faraday::ConnectionFailed) && error.is_a?(Faraday::ConnectionFailed)) ||
        (defined?(Faraday::TimeoutError) && error.is_a?(Faraday::TimeoutError))
    end

    def retry_delay(error)
      headers = error.respond_to?(:response_headers) ? error.response_headers : nil
      value = headers && (headers["retry-after"] || headers["Retry-After"])
      Integer(value, exception: false)
    rescue StandardError
      nil
    end

    def error_kind(error)
      transient?(error) ? "GitHub request retries exhausted" : "GitHub request refused"
    end

    def fail_fetch!(repository, date, reason)
      raise FetchError.new("GitHub fetch failed for #{repository} on #{date}: #{reason}", kind: "github")
    end
  end
end
