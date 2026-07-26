# frozen_string_literal: true

require_relative "test_helper"

class CollectorTest < Minitest::Test
  Window = Prdigest::Clock::Window

  class FakeClock
    attr_reader :dates

    def initialize(window)
      @window = window
      @dates = []
    end

    def window(date)
      @dates << date
      @window
    end
  end

  class FakeGitHub
    attr_reader :requests

    def initialize(digest)
      @digest = digest
      @requests = []
    end

    def fetch(**request)
      @requests << request
      @digest
    end
  end

  def test_collects_a_day_using_the_clock_window_and_configured_scope
    date = Date.new(2026, 1, 15)
    window = Window.new(date, Time.utc(2026, 1, 15), Time.utc(2026, 1, 16))
    digest = Prdigest::DayDigest.build(
      date: date,
      repository_order: ["second/repo", "first/repo"],
      pulls: [],
      line_stats: true
    )
    clock = FakeClock.new(window)
    github = FakeGitHub.new(digest)

    collected = Prdigest::Collector.new(
      clock: clock,
      github: github,
      repositories: ["second/repo", "first/repo"],
      line_stats: true
    ).call(date: date.iso8601)

    assert_same digest, collected
    assert_equal [date], clock.dates
    assert_equal(
      [{
        date: date,
        window: window,
        repositories: ["second/repo", "first/repo"],
        line_stats: true
      }],
      github.requests
    )
  end

  def test_zero_length_day_bypasses_github_and_preserves_the_requested_shape
    date = Date.new(2026, 3, 29)
    window = Window.new(date, Time.utc(2026, 3, 29), Time.utc(2026, 3, 29))
    clock = FakeClock.new(window)
    github = FakeGitHub.new(nil)

    digest = Prdigest::Collector.new(
      clock: clock,
      github: github,
      repositories: ["first/repo", "second/repo"],
      line_stats: false
    ).call(date: date)

    assert_empty github.requests
    assert_equal date, digest.date
    assert_equal ["first/repo", "second/repo"], digest.repositories.map(&:name)
    assert_equal [[], []], digest.repositories.map(&:pull_requests)
    assert_equal false, digest.line_stats
  end
end
