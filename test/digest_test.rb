# frozen_string_literal: true

require_relative "test_helper"

class DigestTest < Minitest::Test
  def test_totals_and_immutability
    pull = Prdigest::PullRequest.new(
      repository: "o/r", number: 1, title: "One", url: "https://github.com/o/r/pull/1",
      author: "dev", merged_at: Time.utc(2026, 1, 1), additions: 4, deletions: 2, commits: 3
    )
    digest = Prdigest::DayDigest.build(date: Date.new(2026, 1, 1), repository_order: ["o/r"], pulls: [pull], line_stats: true)
    assert_equal 1, digest.total_prs
    assert_equal 4, digest.total_additions
    assert_equal 2, digest.total_deletions
    assert_equal 3, digest.total_commits
    assert_predicate digest, :frozen?
    assert_predicate digest.repositories.first.pull_requests, :frozen?
  end

  def test_preserves_repository_order_and_sorts_pulls
    pulls = [
      pull("b/r", 4, Time.utc(2026, 1, 1, 2)),
      pull("a/r", 3, Time.utc(2026, 1, 1, 2)),
      pull("a/r", 2, Time.utc(2026, 1, 1, 1))
    ]
    digest = Prdigest::DayDigest.build(date: Date.new(2026, 1, 1), repository_order: ["a/r", "b/r"], pulls: pulls)
    assert_equal ["a/r", "b/r"], digest.repositories.map(&:name)
    assert_equal [2, 3], digest.repositories.first.pull_requests.map(&:number)
  end

  private

  def pull(repo, number, merged_at)
    Prdigest::PullRequest.new(repository: repo, number: number, title: "PR", url: "https://example.test/#{number}", author: "dev", merged_at: merged_at)
  end
end
