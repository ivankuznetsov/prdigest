# frozen_string_literal: true

require_relative "test_helper"

class FactsTest < Minitest::Test
  def test_serializes_a_versioned_deterministic_facts_document
    digest = Prdigest::DayDigest.build(
      date: Date.new(2026, 1, 15),
      repository_order: ["second/repo", "first/repo"],
      pulls: [
        pull(
          repository: "first/repo",
          number: 12,
          merged_at: Time.new(2026, 1, 15, 13, 30, 0, "+01:00"),
          additions: 21,
          deletions: 8,
          commits: 3
        )
      ],
      line_stats: true
    )

    document = Prdigest::Facts.new(digest: digest, timezone: "Europe/London").to_h

    assert_equal(
      {
        schema: "prdigest-facts",
        schema_version: 1,
        status: "success",
        error: nil,
        digest: {
          date: "2026-01-15",
          timezone: "Europe/London",
          line_stats: true,
          repository_order: ["second/repo", "first/repo"],
          repositories: [
            { name: "second/repo", pull_requests: [] },
            {
              name: "first/repo",
              pull_requests: [{
                number: 12,
                title: "Ship <facts> & prose",
                url: "https://github.com/first/repo/pull/12",
                author: "dev",
                merged_at: "2026-01-15T12:30:00Z",
                additions: 21,
                deletions: 8,
                commits: 3
              }]
            }
          ],
          totals: {
            pull_requests: 1,
            additions: 21,
            deletions: 8,
            commits: 3
          }
        }
      },
      document
    )
    refute_includes document.fetch(:digest).keys, :generated_at
  end

  def test_keeps_disabled_statistic_fields_present_as_null
    digest = Prdigest::DayDigest.build(
      date: Date.new(2026, 1, 15),
      repository_order: ["first/repo"],
      pulls: [pull(repository: "first/repo", number: 1, merged_at: Time.utc(2026, 1, 15))],
      line_stats: false
    )

    document = Prdigest::Facts.new(digest: digest, timezone: "UTC").to_h.fetch(:digest)
    pull_request = document.fetch(:repositories).first.fetch(:pull_requests).first

    assert_nil pull_request.fetch(:additions)
    assert_nil pull_request.fetch(:deletions)
    assert_nil pull_request.fetch(:commits)
    assert_nil document.fetch(:totals).fetch(:additions)
    assert_nil document.fetch(:totals).fetch(:deletions)
    assert_nil document.fetch(:totals).fetch(:commits)
  end

  private

  def pull(repository:, number:, merged_at:, additions: nil, deletions: nil, commits: nil)
    Prdigest::PullRequest.new(
      repository: repository,
      number: number,
      title: "Ship <facts> & prose",
      url: "https://github.com/#{repository}/pull/#{number}",
      author: "dev",
      merged_at: merged_at,
      additions: additions,
      deletions: deletions,
      commits: commits
    )
  end
end
