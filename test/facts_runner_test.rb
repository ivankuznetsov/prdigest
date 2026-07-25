# frozen_string_literal: true

require_relative "test_helper"

class FactsRunnerTest < Minitest::Test
  class FakeClock
    attr_reader :windows

    def initialize(yesterday:)
      @yesterday = yesterday
      @windows = []
    end

    attr_reader :yesterday

    def window(date)
      @windows << date
      Prdigest::Clock::Window.new(date, Time.utc(date.year, date.month, date.day), Time.utc(date.year, date.month, date.day) + 86_400)
    end
  end

  class FakeGitHub
    attr_reader :requests

    def initialize
      @requests = []
    end

    def fetch(date:, window:, repositories:, line_stats:)
      @requests << {
        date: date,
        window: window,
        repositories: repositories,
        line_stats: line_stats
      }
      Prdigest::DayDigest.build(
        date: date,
        repository_order: repositories,
        pulls: [],
        line_stats: line_stats
      )
    end
  end

  def test_defaults_to_configured_timezone_yesterday_and_builds_facts
    config = config_without_telegram
    clock = FakeClock.new(yesterday: Date.new(2026, 1, 15))
    github = FakeGitHub.new
    captured_timezone = nil

    document = Prdigest::Clock.stub(:new, lambda { |timezone:|
      captured_timezone = timezone
      clock
    }) do
      Prdigest::FactsRunner.new(
        config: config,
        env: { "GITHUB_TOKEN" => "synthetic" },
        github: github
      ).call
    end

    assert_equal "prdigest-facts", document.fetch(:schema)
    assert_equal "2026-01-15", document.dig(:digest, :date)
    assert_equal "Europe/London", document.dig(:digest, :timezone)
    assert_equal "Europe/London", captured_timezone
    assert_equal ["owner/repo"], document.dig(:digest, :repository_order)
    assert_equal Date.new(2026, 1, 15), github.requests.fetch(0).fetch(:date)
  end

  def test_explicit_date_and_repository_override_are_forwarded_to_collection
    config = config_without_telegram
    clock = FakeClock.new(yesterday: Date.new(2026, 1, 15))
    github = FakeGitHub.new

    document = Prdigest::FactsRunner.new(
      config: config,
      date: "2026-01-10",
      repositories: ["other/one", "other/two"],
      env: { "GITHUB_TOKEN" => "synthetic" },
      clock: clock,
      github: github
    ).call

    assert_equal "2026-01-10", document.dig(:digest, :date)
    request = github.requests.fetch(0)
    assert_equal ["other/one", "other/two"], request.fetch(:repositories)
    assert_equal config.line_stats?, request.fetch(:line_stats)
  end

  private

  def config_without_telegram
    Prdigest::Config.new({
      "timezone" => "Europe/London",
      "github" => { "repos" => ["owner/repo"] },
      "digest" => { "line_stats" => false }
    })
  end
end
