# frozen_string_literal: true

require_relative "test_helper"
require "cgi"

class RendererTest < Minitest::Test
  def test_renders_normal_day_from_golden_file
    digest = day([pull("owner/repo", 7, "Ship feature", "alice")])
    output = renderer.render(digest)
    assert_equal fixture("normal_day.html"), output.chunks.fetch(0)
    assert_equal "rendered", output.outcome
  end

  def test_renders_repositories_in_config_order_and_complete_stats
    digest = day([
      pull("second/repo", 2, "Second", "bob", additions: 3, deletions: 1, commits: 1),
      pull("first/repo", 1, "First", "alice", additions: 4, deletions: 2, commits: 2)
    ], repositories: ["first/repo", "second/repo"], line_stats: true)
    assert_equal fixture("multi_repo_day.html"), renderer.render(digest).chunks.fetch(0)
  end

  def test_escapes_hostile_text_and_attributes
    digest = day([pull("o&/<r>", 1, "<b>x & \"y\"</b> 😀", "a<&")], repositories: ["o&/<r>"])
    chunk = renderer.render(digest).chunks.fetch(0)
    assert_equal fixture("hostile_titles.html"), chunk
    refute_includes chunk, "<b>x"
    assert_equal 1, chunk.scan("<a href=").length
  end

  def test_empty_day_is_sent_or_intentionally_suppressed
    digest = day([])
    output = renderer(send_empty: true, empty_message: "Nothing <merged> on {date} & done").render(digest)
    assert_equal fixture("empty_day.html"), output.chunks.fetch(0)

    suppressed = renderer(send_empty: false).render(digest)
    assert_empty suppressed.chunks
    assert_equal "suppressed_empty", suppressed.outcome
  end

  def test_splits_large_repository_with_valid_bounded_chunks
    pulls = 18.times.map { |index| pull("owner/repo", index + 1, "T" * 350, "developer") }
    chunks = renderer(limit: 900).render(day(pulls)).chunks
    assert_operator chunks.length, :>, 1
    chunks.each do |chunk|
      assert_operator Prdigest::Renderer.parsed_length(chunk), :<=, 900
      assert_equal chunk.scan("<b>").length, chunk.scan("</b>").length
      assert_equal chunk.scan("<a ").length, chunk.scan("</a>").length
    end
    rendered_numbers = chunks.flat_map { |chunk| chunk.scan(/#(\d+)/).flatten.map(&:to_i) }
    assert_equal (1..18).to_a, rendered_numbers
    assert_equal 1, chunks.sum { |chunk| chunk.scan("<b>Total:</b>").length }
    assert_includes chunks.last, "<b>Total:</b>"
  end

  def test_rejects_an_impossible_single_entry
    digest = day([pull("o/r", 1, "X" * 1_000, "dev")])
    assert_raises(Prdigest::RenderError) { renderer(limit: 100).render(digest) }
  end

  private

  def renderer(limit: 4096, send_empty: true, empty_message: "unused")
    Prdigest::Renderer.new(send_empty: send_empty, empty_message: empty_message, limit: limit)
  end

  def day(pulls, repositories: nil, line_stats: false)
    Prdigest::DayDigest.build(
      date: Date.new(2026, 1, 15),
      repository_order: repositories || pulls.map(&:repository).uniq.then { |repos| repos.empty? ? ["owner/repo"] : repos },
      pulls: pulls,
      line_stats: line_stats
    )
  end

  def pull(repo, number, title, author, additions: nil, deletions: nil, commits: nil)
    Prdigest::PullRequest.new(
      repository: repo, number: number, title: title,
      url: "https://github.com/#{CGI.escape(repo)}/pull/#{number}?q=\"&x=<tag>", author: author,
      merged_at: Time.utc(2026, 1, 15, 10, number), additions: additions, deletions: deletions, commits: commits
    )
  end

  def fixture(name)
    File.read(File.join(__dir__, "fixtures", "renderer", name)).chomp
  end
end
