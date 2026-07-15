# frozen_string_literal: true

module Prdigest
  # Placeholder runner. Real GitHub fetch + Telegram send come next.
  class Runner
    def initialize(config:, date: nil, dry_run: false)
      @config = config
      @date = date
      @dry_run = dry_run
    end

    def call
      {
        ok: true,
        status: "not_implemented",
        date: @date,
        dry_run: @dry_run,
        repos: @config.repos,
        chat_id: @config.chat_id,
        message: scaffold_message
      }
    end

    private

    def scaffold_message
      day = @date || "yesterday"
      "Merged PR digest — #{day}\n" \
        "Total: 0 PRs\n" \
        "(scaffold only — implementation next)\n" \
        "Repos: #{@config.repos.join(', ')}"
    end
  end
end
