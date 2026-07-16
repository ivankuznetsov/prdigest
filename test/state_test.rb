# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"

class StateTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    @path = File.join(@dir, "state.json")
    @state = Prdigest::State.new(path: @path, timezone: "Europe/London")
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_missing_state_is_first_run
    assert_nil @state.read(yesterday: Date.new(2026, 1, 10)).last_digested_date
  end

  def test_round_trips_versioned_state_with_restrictive_permissions
    skip_audit = { start_date: Date.new(2026, 1, 1), end_date: Date.new(2026, 1, 3), notice_pending: true }
    @state.write(last_digested_date: Date.new(2026, 1, 3), last_skip: skip_audit)
    record = @state.read(yesterday: Date.new(2026, 1, 10))
    assert_equal Date.new(2026, 1, 3), record.last_digested_date
    assert_equal skip_audit, record.last_skip
    assert_equal 0o600, File.stat(@path).mode & 0o777
    assert_empty Dir.glob(File.join(@dir, ".state.json.tmp-*"))
  end

  def test_rejects_malformed_unsupported_mismatched_and_future_state
    invalid = [
      "not json",
      JSON.generate(version: 2, timezone: "Europe/London", last_digested_date: "2026-01-01"),
      JSON.generate(version: 1, timezone: "UTC", last_digested_date: "2026-01-01"),
      JSON.generate(version: 1, timezone: "Europe/London", last_digested_date: "bad"),
      JSON.generate(version: 1, timezone: "Europe/London", last_digested_date: "2026-01-11"),
      JSON.generate(version: 1, timezone: "Europe/London"),
      JSON.generate(
        version: 1, timezone: "Europe/London", last_digested_date: "2026-01-03",
        last_skip: { start_date: "2026-01-01", end_date: "2026-01-04", notice_pending: true }
      )
    ]
    invalid.each do |payload|
      File.write(@path, payload)
      assert_raises(Prdigest::StateError) { @state.read(yesterday: Date.new(2026, 1, 10)) }
    end
  end

  def test_failed_atomic_replace_preserves_previous_file
    @state.write(last_digested_date: Date.new(2026, 1, 1))
    original = File.binread(@path)
    state = Prdigest::State.new(path: @path, timezone: "Europe/London", rename: ->(*) { raise Errno::EACCES })
    assert_raises(Prdigest::StateError) { state.write(last_digested_date: Date.new(2026, 1, 2)) }
    assert_equal original, File.binread(@path)
    assert_empty Dir.glob(File.join(@dir, ".state.json.tmp-*"))
  end
end
