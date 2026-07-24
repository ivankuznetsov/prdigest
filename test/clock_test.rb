# frozen_string_literal: true

require_relative "test_helper"

class ClockTest < Minitest::Test
  def test_london_spring_window_is_23_hours
    window = clock("Europe/London").window(Date.new(2026, 3, 29))
    assert_equal Time.utc(2026, 3, 29), window.start_time
    assert_equal Time.utc(2026, 3, 29, 23), window.end_time
  end

  def test_london_fall_window_is_25_hours
    window = clock("Europe/London").window(Date.new(2026, 10, 25))
    assert_equal Time.utc(2026, 10, 24, 23), window.start_time
    assert_equal Time.utc(2026, 10, 26), window.end_time
  end

  def test_tokyo_window_crosses_utc_date
    window = clock("Asia/Tokyo").window(Date.new(2026, 1, 15))
    assert_equal Time.utc(2026, 1, 14, 15), window.start_time
    assert_equal Time.utc(2026, 1, 15, 15), window.end_time
    assert window.cover?(window.start_time)
    refute window.cover?(window.end_time)
  end

  def test_yesterday_uses_configured_zone
    now = Time.utc(2026, 1, 15, 23, 30)
    assert_equal Date.new(2026, 1, 15), clock("Asia/Tokyo", now).yesterday
    assert_equal Date.new(2026, 1, 14), clock("America/Los_Angeles", now).yesterday
  end

  def test_nonexistent_and_ambiguous_midnights
    santiago = clock("America/Santiago").window(Date.new(2026, 9, 6))
    assert_equal Time.utc(2026, 9, 6, 4), santiago.start_time
    assert_equal Time.utc(2026, 9, 7, 3), santiago.end_time

    havana = clock("America/Havana").window(Date.new(2026, 11, 1))
    assert_equal Time.utc(2026, 11, 1, 4), havana.start_time
    assert_equal Time.utc(2026, 11, 2, 5), havana.end_time
  end

  private

  def clock(zone, now = Time.utc(2026, 1, 16))
    Prdigest::Clock.new(timezone: zone, now: -> { now })
  end
end
