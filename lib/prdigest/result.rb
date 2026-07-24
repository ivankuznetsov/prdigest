# frozen_string_literal: true

module Prdigest
  class Result
    SCHEMA = "prdigest-result"
    SCHEMA_VERSION = 1
    REQUIRED_FIELDS = %i[
      status mode requested_days settled_days skipped_days failed_date remaining_days error
    ].freeze
    EXIT_CODES = {
      "config" => 2, "cli" => 2, "refusal" => 2,
      "github" => 3,
      "telegram" => 4, "telegram_refused" => 4, "telegram_permanent" => 4,
      "telegram_ambiguous" => 4, "delivery_checkpoint" => 4,
      "delivery_checkpoint_permanent" => 4,
      "state" => 5
    }.freeze

    attr_reader(*REQUIRED_FIELDS, :chunks, :delivery)

    def initialize(status:, mode:, requested_days: [], settled_days: [], skipped_days: [],
                   failed_date: nil, remaining_days: [], error: nil, chunks: [], delivery: nil)
      @status = status.to_s.freeze
      @mode = mode.to_s.freeze
      @requested_days = Array(requested_days).freeze
      @settled_days = Array(settled_days).freeze
      @skipped_days = Array(skipped_days).freeze
      @failed_date = failed_date
      @remaining_days = Array(remaining_days).freeze
      @error = error&.transform_keys(&:to_sym)&.freeze
      @chunks = Array(chunks).map(&:to_s).freeze
      @delivery = delivery&.transform_keys(&:to_sym)&.freeze
      freeze
    end

    def self.failure(mode:, error_kind:, message:, requested_days: [], settled_days: [], skipped_days: [],
                     failed_date: nil, remaining_days: [], chunks: [], delivery: nil)
      progress = !settled_days.empty? || !skipped_days.empty?
      new(
        status: progress ? "partial_failure" : "failure",
        mode: mode,
        requested_days: requested_days,
        settled_days: settled_days,
        skipped_days: skipped_days,
        failed_date: failed_date,
        remaining_days: remaining_days,
        error: { kind: error_kind.to_s, message: message.to_s },
        chunks: chunks,
        delivery: delivery
      )
    end

    def exit_code
      return 0 if %w[success dry_run].include?(status)
      return 6 if status == "partial_failure"
      EXIT_CODES.fetch(error && error[:kind], 1)
    end

    def to_h
      {
        schema: SCHEMA,
        schema_version: SCHEMA_VERSION,
        status: status,
        mode: mode,
        requested_days: serialize_dates(requested_days),
        settled_days: serialize_dates(settled_days),
        skipped_days: serialize_dates(skipped_days),
        failed_date: failed_date&.to_s,
        remaining_days: serialize_dates(remaining_days),
        error: error,
        chunks: chunks,
        delivery: delivery
      }
    end

    private

    def serialize_dates(values)
      values.map(&:to_s)
    end
  end
end
