# frozen_string_literal: true

require "date"

module Prdigest
  PullRequest = Data.define(
    :repository, :number, :title, :url, :author, :merged_at,
    :additions, :deletions, :commits
  ) do
    def initialize(repository:, number:, title:, url:, author:, merged_at:, additions: nil, deletions: nil, commits: nil)
      super(
        repository: repository.to_s.freeze,
        number: Integer(number),
        title: title.to_s.freeze,
        url: url.to_s.freeze,
        author: author.to_s.freeze,
        merged_at: merged_at.utc.freeze,
        additions: additions && Integer(additions),
        deletions: deletions && Integer(deletions),
        commits: commits && Integer(commits)
      )
    end
  end

  RepositoryDigest = Data.define(:name, :pull_requests)

  DayDigest = Data.define(:date, :repositories, :line_stats) do
    def self.build(date:, repository_order:, pulls:, line_stats: false)
      grouped = pulls.group_by(&:repository)
      sections = repository_order.map do |name|
        sorted = Array(grouped[name]).sort_by { |pull| [pull.merged_at, pull.number] }.freeze
        RepositoryDigest.new(name.to_s.freeze, sorted)
      end.freeze
      new(Date.iso8601(date.to_s), sections, line_stats == true)
    end

    def total_prs
      repositories.sum { |section| section.pull_requests.length }
    end

    def total_additions
      stat_total(:additions)
    end

    def total_deletions
      stat_total(:deletions)
    end

    def total_commits
      stat_total(:commits)
    end

    private

    def stat_total(name)
      return nil unless line_stats
      repositories.sum { |section| section.pull_requests.sum { |pull| pull.public_send(name) } }
    end
  end
end
