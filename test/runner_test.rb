# frozen_string_literal: true

require_relative "test_helper"

class RunnerTest < Minitest::Test
  Window = Prdigest::Clock::Window

  class FakeClock
    def initialize(yesterday)
      @yesterday = yesterday
    end

    attr_reader :yesterday

    def window(date)
      Window.new(date, Time.utc(date.year, date.month, date.day), Time.utc(date.year, date.month, date.day) + 86_400)
    end
  end

  class FakeState
    attr_reader :writes, :reads

    def initialize(record, write_error: nil)
      @record = record
      @write_error = write_error
      @writes = []
      @reads = 0
    end

    def read(yesterday:)
      @reads += 1
      @record
    end

    def write(**attributes)
      raise @write_error if @write_error
      @writes << attributes
      Prdigest::State::Record.new(attributes[:last_digested_date], attributes[:last_skip])
    end
  end

  class FakeGitHub
    attr_reader :dates

    def initialize(error: nil)
      @error = error
      @dates = []
    end

    def fetch(date:, repositories:, line_stats:, window:)
      @dates << date
      raise @error if @error
      Prdigest::DayDigest.build(date: date, repository_order: repositories, pulls: [], line_stats: line_stats)
    end
  end

  class FakeRenderer
    def initialize(chunks: ["digest"], outcome: "rendered", error: nil)
      @output = Prdigest::Renderer::Output.new(chunks, outcome)
      @error = error
    end

    def render(_digest)
      raise @error if @error
      @output
    end
  end

  class FakeTelegram
    attr_reader :batches

    def initialize(error: nil)
      @error = error
      @batches = []
    end

    def deliver(chunks)
      @batches << chunks
      raise @error if @error
    end
  end

  def test_first_scheduled_run_sends_and_checkpoints_yesterday
    state = FakeState.new(Prdigest::State::Record.new(nil, nil))
    github = FakeGitHub.new
    telegram = FakeTelegram.new
    result = runner(state: state, github: github, telegram: telegram).call
    assert_equal "success", result.status
    assert_equal [date(10)], result.requested_days
    assert_equal [date(10)], result.settled_days
    assert_equal [date(10)], github.dates
    assert_equal [date(10)], state.writes.map { |write| write[:last_digested_date] }
    assert_equal [["digest"]], telegram.batches
  end

  def test_over_cap_skip_is_checkpointed_before_fetch_failure
    state = FakeState.new(Prdigest::State::Record.new(date(0), nil))
    github = FakeGitHub.new(error: Prdigest::FetchError.new("safe", kind: "github"))
    result = runner(state: state, github: github, max_catchup_days: 7).call
    assert_equal "partial_failure", result.status
    assert_equal 6, result.exit_code
    assert_equal [date(1), date(2), date(3)], result.skipped_days
    assert_equal date(4), result.failed_date
    assert_equal date(3), state.writes.first[:last_digested_date]
    assert_equal true, state.writes.first[:last_skip][:notice_pending]
  end

  def test_skip_checkpoint_failure_preserves_all_requested_days_as_remaining
    state = FakeState.new(
      Prdigest::State::Record.new(date(0), nil),
      write_error: Prdigest::StateError.new("safe")
    )

    result = runner(state: state, github: FakeGitHub.new, max_catchup_days: 7).call

    assert_equal "failure", result.status
    assert_equal (date(4)..date(10)).to_a, result.requested_days
    assert_equal result.requested_days, result.remaining_days
    assert_nil result.failed_date
  end

  def test_recovered_skip_notice_is_cleared_after_next_settlement
    audit = { start_date: date(1), end_date: date(3), notice_pending: true }
    state = FakeState.new(Prdigest::State::Record.new(date(3), audit))
    result = runner(state: state, github: FakeGitHub.new, max_catchup_days: 7).call
    assert_equal [date(1), date(2), date(3)], result.skipped_days
    assert_equal false, state.writes.first[:last_skip][:notice_pending]
  end

  def test_delivery_or_state_failure_leaves_current_day_unsettled
    state = FakeState.new(Prdigest::State::Record.new(nil, nil))
    telegram = FakeTelegram.new(error: Prdigest::SendError.new("safe"))
    result = runner(state: state, github: FakeGitHub.new, telegram: telegram).call
    assert_equal date(10), result.failed_date
    assert_empty result.settled_days
    assert_empty state.writes
    assert_equal 4, result.exit_code

    failing_state = FakeState.new(Prdigest::State::Record.new(nil, nil), write_error: Prdigest::StateError.new("safe"))
    result = runner(state: failing_state, github: FakeGitHub.new).call
    assert_equal 5, result.exit_code
    assert_empty result.settled_days
  end

  def test_replay_and_dry_run_never_construct_state_or_telegram
    github = FakeGitHub.new
    forbidden = -> { flunk "dependency must not be constructed" }
    replay = runner(
      date: "2025-01-01", dry_run: true, github: github,
      state_factory: forbidden, telegram_factory: forbidden
    ).call
    assert_equal "explicit_date_replay", replay.mode
    assert_equal "dry_run", replay.status
    assert_equal [Date.new(2025, 1, 1)], replay.requested_days
    assert_equal ["digest"], replay.chunks

    scheduled = runner(dry_run: true, github: github, state_factory: forbidden, telegram_factory: forbidden).call
    assert_equal "scheduled", scheduled.mode
    assert_equal [date(10)], scheduled.requested_days
  end

  def test_suppressed_empty_settles_without_telegram
    state = FakeState.new(Prdigest::State::Record.new(nil, nil))
    result = runner(
      state: state, github: FakeGitHub.new,
      renderer: FakeRenderer.new(chunks: [], outcome: "suppressed_empty"),
      telegram_factory: -> { flunk "Telegram must not be constructed" }
    ).call
    assert_equal "success", result.status
    assert_equal [date(10)], result.settled_days
  end

  def test_inspection_does_not_expose_retained_environment_tokens
    github_token = "synthetic-github-secret"
    telegram_token = "synthetic-telegram-secret"
    instance = runner(
      github: FakeGitHub.new,
      env: { "GITHUB_TOKEN" => github_token, "TELEGRAM_BOT_TOKEN" => telegram_token }
    )

    [instance.inspect, instance.to_s].each do |surface|
      refute_includes surface, github_token
      refute_includes surface, telegram_token
    end
  end

  private

  def runner(state: nil, github:, telegram: FakeTelegram.new, renderer: FakeRenderer.new,
             date: nil, dry_run: false, max_catchup_days: 7,
             state_factory: nil, telegram_factory: nil, env: {})
    config = Struct.new(:timezone, :repos, :line_stats?, :max_catchup_days).new("UTC", ["o/r"], false, max_catchup_days)
    Prdigest::Runner.new(
      config: config, date: date, dry_run: dry_run, clock: FakeClock.new(self.date(10)),
      state_factory: state_factory || -> { state || FakeState.new(Prdigest::State::Record.new(nil, nil)) },
      github: github, renderer: renderer, telegram_factory: telegram_factory || -> { telegram }, env: env
    )
  end

  def date(day)
    Date.new(2026, 1, 1) + day
  end
end
