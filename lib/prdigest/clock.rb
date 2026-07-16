# frozen_string_literal: true

require "date"
require "time"
require "tzinfo"

module Prdigest
  class Clock
    Window = Data.define(:local_date, :start_time, :end_time) do
      def cover?(time)
        time >= start_time && time < end_time
      end

      def zero_length?
        start_time == end_time
      end
    end

    def initialize(timezone:, now: -> { Time.now })
      @timezone = TZInfo::Timezone.get(timezone)
      @now = now
    end

    def yesterday
      (@timezone.to_local(@now.call.utc).to_date - 1)
    end

    def window(local_date)
      date = Date.iso8601(local_date.to_s)
      Window.new(date, resolve_midnight(date), resolve_midnight(date + 1))
    end

    private

    def resolve_midnight(date)
      local = Time.utc(date.year, date.month, date.day)
      periods = @timezone.periods_for_local(local)
      return periods.map { |period| (local - period.utc_total_offset).utc }.min unless periods.empty?

      transition = @timezone.transitions_up_to(local + 172_800, local - 172_800).find do |candidate|
        before = Time.at(candidate.timestamp_value + candidate.previous_offset.utc_total_offset).utc
        after = Time.at(candidate.timestamp_value + candidate.offset.utc_total_offset).utc
        after > before && local >= before && local < after
      end
      raise ConfigError, "cannot resolve local midnight for #{date}" unless transition

      Time.at(transition.timestamp_value).utc
    end
  end
end
