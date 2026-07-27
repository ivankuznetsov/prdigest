# frozen_string_literal: true

require_relative "test_helper"

class ProseRendererTest < Minitest::Test
  def test_rejects_blank_provider_output
    ["", " \n\t "].each do |text|
      error = assert_raises(Prdigest::RenderError) { renderer.render(text) }
      assert_equal "prose_render", error.kind
      assert_match(/blank/, error.message)
    end
  end

  def test_rejects_terminal_control_characters
    [
      "\e[31mred\e[0m",
      "\e]0;forged title\e\\safe",
      "ring\a",
      "red\u009B31m"
    ].each do |text|
      error = assert_raises(Prdigest::RenderError) { renderer.render(text) }
      assert_equal "prose_render", error.kind
      assert_match(/control characters/, error.message)
    end
  end

  def test_allows_tabs_and_newlines
    text = "Repository\tSummary\nowner/repo\tMerged"

    output = renderer.render(text)

    assert_equal text, output.chunks.join
  end

  def test_keeps_provider_output_as_plain_text
    text = "<b>trusted?</b> & \"quoted\" 'value'"

    output = renderer.render(text)

    assert_equal "rendered", output.outcome
    assert_equal text, output.chunks.fetch(0)
  end

  def test_preserves_unicode_and_exact_newlines_across_chunks
    text = "Alpha 😀\nβeta & café\n終わり"

    output = renderer(limit: 7).render(text)

    assert_operator output.chunks.length, :>, 1
    assert_equal text, output.chunks.join
    output.chunks.each do |chunk|
      assert_operator chunk.length, :<=, 7
      assert_predicate chunk, :valid_encoding?
    end
  end

  def test_long_output_round_trips_without_loss_and_stays_within_telegram_limit
    text = (["<tag>& 😀 alpha\n", "βeta 'quote' \"double\"\n"] * 400).join

    output = renderer.render(text)

    assert_operator output.chunks.length, :>, 1
    assert_equal text, output.chunks.join
    output.chunks.each do |chunk|
      assert_operator chunk.length, :<=, 4_096
    end
  end

  private

  def renderer(limit: 4_096)
    Prdigest::ProseRenderer.new(limit: limit)
  end
end
