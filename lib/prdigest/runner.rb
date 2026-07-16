# frozen_string_literal: true

require "date"

module Prdigest
  class Runner
    def initialize(config:, date: nil, dry_run: false, clock: nil, state_factory: nil,
                   github: nil, renderer: nil, telegram_factory: nil, env: ENV)
      @config = config
      @date = date && Date.iso8601(date.to_s)
      @dry_run = dry_run
      @clock = clock || Clock.new(timezone: config.timezone)
      @state_factory = state_factory || -> { State.new(path: config.state_path, timezone: config.timezone) }
      @env = env
      @github = github || GitHub.new(token: config.github_token(env))
      @renderer = renderer || Renderer.new(send_empty: config.send_empty?, empty_message: config.empty_message)
      @telegram_factory = telegram_factory || lambda {
        Telegram.new(
          token: config.telegram_token(env),
          chat_id: config.chat_id,
          allowlist: config.chat_id_allowlist
        )
      }
    end

    def call
      mode = @date ? "explicit_date_replay" : "scheduled"
      requested = []
      settled = []
      skipped = []
      chunks = []
      failed_date = nil
      state = nil
      skip_audit = nil

      if @dry_run || @date
        requested = [@date || @clock.yesterday]
      else
        state = @state_factory.call
        yesterday = @clock.yesterday
        record = state.read(yesterday: yesterday)
        skip_audit = record.last_skip
        skipped.concat(expand_skip(skip_audit)) if skip_audit && skip_audit[:notice_pending]
        schedule = Schedule.new(
          yesterday: yesterday,
          last_digested_date: record.last_digested_date,
          max_catchup_days: @config.max_catchup_days
        ).call
        requested = schedule.requested_days
        unless schedule.skipped_days.empty?
          skip_audit = merge_skip_audit(skip_audit, schedule.skipped_days)
          state.write(last_digested_date: schedule.skipped_days.last, last_skip: skip_audit)
          skipped |= schedule.skipped_days
        end
      end

      telegram = nil
      requested.each do |date|
        failed_date = date
        window = @clock.window(date)
        digest = if window.zero_length?
                   DayDigest.build(date: date, repository_order: @config.repos, pulls: [], line_stats: @config.line_stats?)
                 else
                   @github.fetch(
                     date: date,
                     window: window,
                     repositories: @config.repos,
                     line_stats: @config.line_stats?
                   )
                 end
        rendered = @renderer.render(digest)
        if @dry_run
          chunks.concat(rendered.chunks)
          next
        end

        unless rendered.chunks.empty?
          telegram ||= @telegram_factory.call
          telegram.deliver(rendered.chunks)
        end
        if state
          if skip_audit
            skip_audit = skip_audit.merge(notice_pending: false)
          end
          state.write(last_digested_date: date, last_skip: skip_audit)
        end
        settled << date
        failed_date = nil
      end

      Result.new(
        status: @dry_run ? "dry_run" : "success",
        mode: mode,
        requested_days: requested,
        settled_days: settled,
        skipped_days: skipped,
        chunks: chunks
      )
    rescue StandardError => e
      Result.failure(
        mode: mode || (@date ? "explicit_date_replay" : "scheduled"),
        error_kind: error_kind(e),
        message: safe_message(e),
        requested_days: requested || [],
        settled_days: settled || [],
        skipped_days: skipped || [],
        failed_date: failed_date,
        remaining_days: remaining_days(requested || [], failed_date),
        chunks: chunks || []
      )
    end

    private

    def expand_skip(audit)
      return [] unless audit
      (audit.fetch(:start_date)..audit.fetch(:end_date)).to_a
    end

    def merge_skip_audit(existing, dates)
      start_date = if existing && existing[:notice_pending]
                     [existing[:start_date], dates.first].min
                   else
                     dates.first
                   end
      { start_date: start_date, end_date: dates.last, notice_pending: true }
    end

    def remaining_days(requested, failed_date)
      return [] unless failed_date
      index = requested.index(failed_date)
      index ? requested.drop(index) : [failed_date]
    end

    def error_kind(error)
      case error
      when ConfigError then "config"
      when FetchError then error.kind
      when SendError then error.kind
      when StateError then "state"
      when RenderError then error.kind
      else "internal"
      end
    end

    def safe_message(error)
      message = error.is_a?(Error) ? error.message : "unexpected failure (#{error.class})"
      secrets = []
      secrets << @config.github_token(@env) if @config.respond_to?(:github_token)
      secrets << @config.telegram_token(@env) if @config.respond_to?(:telegram_token)
      secrets.compact.reject(&:empty?).reduce(message.dup) { |safe, secret| safe.gsub(secret, "[REDACTED]") }
    end
  end
end
