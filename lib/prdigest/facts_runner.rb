# frozen_string_literal: true

require "date"

module Prdigest
  class FactsRunner
    def initialize(config:, date: nil, repositories: nil, env: ENV, clock: nil, github: nil)
      @config = config
      @date = date && Date.iso8601(date.to_s)
      @repositories = repositories || config.repos
      @clock = clock || Clock.new(timezone: config.timezone)
      @github = github || GitHub.new(token: config.github_token(env))
    end

    def call
      date = @date || @clock.yesterday
      digest = Collector.new(
        clock: @clock,
        github: @github,
        repositories: @repositories,
        line_stats: @config.line_stats?
      ).call(date: date)
      Facts.new(digest: digest, timezone: @config.timezone).to_h
    end

    def inspect
      "#<#{self.class} date=#{@date || "yesterday"} credentials=[REDACTED]>"
    end

    alias to_s inspect
  end
end
