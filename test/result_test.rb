# frozen_string_literal: true

require_relative "test_helper"

class ResultTest < Minitest::Test
  def test_envelope_always_contains_required_fields
    result = Prdigest::Result.new(status: "success", mode: "scheduled")
    assert_equal "prdigest-result", result.to_h.fetch(:schema)
    assert_equal 1, result.to_h.fetch(:schema_version)
    assert_equal %i[status mode requested_days settled_days skipped_days failed_date remaining_days error],
                 result.to_h.keys.drop(2).first(8)
    assert_equal 0, result.exit_code
  end

  def test_maps_failures_and_partial_progress_to_public_exits
    {
      "config" => 2, "cli" => 2, "github" => 3,
      "telegram" => 4, "telegram_refused" => 4, "telegram_permanent" => 4,
      "telegram_ambiguous" => 4, "delivery_checkpoint" => 4,
      "delivery_checkpoint_permanent" => 4,
      "state" => 5, "render" => 1
    }.each do |kind, code|
      result = Prdigest::Result.failure(mode: "scheduled", error_kind: kind, message: "safe")
      assert_equal code, result.exit_code
    end
    result = Prdigest::Result.failure(mode: "scheduled", error_kind: "github", message: "safe", settled_days: [Date.new(2026, 1, 1)])
    assert_equal "partial_failure", result.status
    assert_equal 6, result.exit_code
    assert_equal "github", result.error.fetch(:kind)
  end
end
