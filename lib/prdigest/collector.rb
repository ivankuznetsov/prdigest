# frozen_string_literal: true

require "date"

module Prdigest
  class Collector
    def initialize(clock:, github:, repositories:, line_stats: false)
      @clock = clock
      @github = github
      @repositories = Array(repositories).map { |repository| repository.to_s.freeze }.freeze
      @line_stats = line_stats == true
    end

    def call(date:)
      date = Date.iso8601(date.to_s)
      window = @clock.window(date)
      return empty_digest(date) if window.zero_length?

      @github.fetch(
        date: date,
        window: window,
        repositories: @repositories,
        line_stats: @line_stats
      )
    end

    private

    def empty_digest(date)
      DayDigest.build(
        date: date,
        repository_order: @repositories,
        pulls: [],
        line_stats: @line_stats
      )
    end
  end
end
