# frozen_string_literal: true

require "date"

module Prdigest
  class Schedule
    Result = Data.define(:skipped_days, :requested_days)

    def initialize(yesterday:, last_digested_date:, max_catchup_days:)
      @yesterday = Date.iso8601(yesterday.to_s)
      @last_digested_date = last_digested_date && Date.iso8601(last_digested_date.to_s)
      @max_catchup_days = Integer(max_catchup_days)
    end

    def call
      raise ArgumentError, "max_catchup_days must be from 1 to 30" unless (1..30).cover?(@max_catchup_days)
      raise ArgumentError, "last digested date is in the future" if @last_digested_date && @last_digested_date > @yesterday

      owed = if @last_digested_date.nil?
               [@yesterday]
             elsif @last_digested_date == @yesterday
               []
             else
               ((@last_digested_date + 1)..@yesterday).to_a
             end
      split = [owed.length - @max_catchup_days, 0].max
      Result.new(owed.first(split).freeze, owed.drop(split).freeze)
    end
  end
end
