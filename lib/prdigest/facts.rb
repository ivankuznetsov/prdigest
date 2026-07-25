# frozen_string_literal: true

require "time"

module Prdigest
  class Facts
    SCHEMA = "prdigest-facts"
    SCHEMA_VERSION = 1

    def initialize(digest:, timezone:)
      @digest = digest
      @timezone = timezone.to_s.freeze
    end

    def to_h
      {
        schema: SCHEMA,
        schema_version: SCHEMA_VERSION,
        status: "success",
        error: nil,
        digest: serialize_digest
      }
    end

    private

    def serialize_digest
      {
        date: @digest.date.iso8601,
        timezone: @timezone,
        line_stats: @digest.line_stats,
        repository_order: @digest.repositories.map(&:name),
        repositories: @digest.repositories.map { |repository| serialize_repository(repository) },
        totals: {
          pull_requests: @digest.total_prs,
          additions: @digest.total_additions,
          deletions: @digest.total_deletions,
          commits: @digest.total_commits
        }
      }
    end

    def serialize_repository(repository)
      {
        name: repository.name,
        pull_requests: repository.pull_requests.map { |pull| serialize_pull(pull) }
      }
    end

    def serialize_pull(pull)
      {
        number: pull.number,
        title: pull.title,
        url: pull.url,
        author: pull.author,
        merged_at: pull.merged_at.utc.iso8601,
        additions: pull.additions,
        deletions: pull.deletions,
        commits: pull.commits
      }
    end
  end
end
