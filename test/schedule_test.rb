# frozen_string_literal: true

require_relative "test_helper"

class ScheduleTest < Minitest::Test
  def test_first_run_only_requests_yesterday
    result = Prdigest::Schedule.new(yesterday: date(10), last_digested_date: nil, max_catchup_days: 7).call
    assert_equal [date(10)], result.requested_days
    assert_empty result.skipped_days
  end

  def test_current_state_requests_nothing
    result = schedule(last: 10, cap: 7)
    assert_empty result.requested_days
    assert_empty result.skipped_days
  end

  def test_backlog_is_oldest_first
    result = schedule(last: 5, cap: 7)
    assert_equal (6..10).map { |day| date(day) }, result.requested_days
  end

  def test_ten_day_backlog_skips_oldest_three
    result = Prdigest::Schedule.new(yesterday: date(10), last_digested_date: date(0), max_catchup_days: 7).call
    assert_equal (1..3).map { |day| date(day) }, result.skipped_days
    assert_equal (4..10).map { |day| date(day) }, result.requested_days
  end

  def test_rejects_invalid_caps_and_future_state
    [0, 31].each do |cap|
      assert_raises(ArgumentError) { schedule(last: 1, cap: cap) }
    end
    assert_raises(ArgumentError) { schedule(last: 11, cap: 7) }
  end

  private

  def schedule(last:, cap:)
    Prdigest::Schedule.new(yesterday: date(10), last_digested_date: date(last), max_catchup_days: cap).call
  end

  def date(day)
    Date.new(2026, 1, 1) + day
  end
end
