# frozen_string_literal: true

require_relative "test_helper"

class DocumentTest < Minitest::Test
  class FakeGenerator
    attr_reader :prompts

    def initialize(value: "Readable digest", error: nil)
      @value = value
      @error = error
      @prompts = []
    end

    def generate(prompt)
      @prompts << prompt
      raise @error if @error

      @value
    end
  end

  def test_generates_from_precollected_evidence_without_configuration_or_side_effects
    generator = FakeGenerator.new
    facts = {
      schema: "prdigest-facts",
      digest: { repositories: [{ name: "owner/repo", pull_requests: [{
        number: 12, title: "Maintenance", description: "Adds concrete recovery behavior",
        patches: [{ path: "lib/recovery.rb", patch: "def recover; end", truncated: false }],
        patches_omitted: 0
      }] }] }
    }

    assert_equal "Readable digest", Prdigest::Document.generate(facts: facts, generator: generator)
    assert_equal facts, generator.prompts.fetch(0)
    prompt = Prdigest::Document.prompt(facts)
    assert_includes prompt, "user-facing"
    assert_includes prompt, "Adds concrete recovery behavior"
    assert_includes prompt, "lib/recovery.rb"
    assert_includes prompt, "Do not invent facts"
  end

  def test_prompt_contract_requires_concise_editorial_markdown_without_implementation_boilerplate
    instructions = Prdigest::Document::INSTRUCTIONS

    assert_includes instructions, "editorial Markdown"
    assert_includes instructions, "# title that names the digest date"
    assert_includes instructions, "one short opening"
    assert_includes instructions, "## project"
    assert_includes instructions, "one or two short"
    assert_includes instructions, "user-facing sentences"
    assert_includes instructions, "full Markdown links"
    assert_includes instructions, "custom HTML"
    assert_includes instructions, "title dump"
    assert_includes instructions, "minimal jargon"
    assert_includes instructions, "Omit file paths"
    assert_includes instructions, "low-impact tooling"
    assert_includes instructions, "generic evidence or partial-diff disclaimer"
    assert_includes instructions, "250 to 400 words for eleven PRs"
    assert_includes instructions, "Do not invent facts or claim a complete diff"
  end

  def test_preserves_generator_errors
    error = Prdigest::GenerationError.new("generator unavailable")
    assert_raises(Prdigest::GenerationError) do
      Prdigest::Document.generate(facts: {}, generator: FakeGenerator.new(error: error))
    end
  end

  def test_rejects_blank_non_text_and_control_character_generator_output
    ["", " \n", :not_text, "safe\u0007unsafe"].each do |output|
      error = assert_raises(Prdigest::GenerationError) do
        Prdigest::Document.generate(facts: {}, generator: FakeGenerator.new(value: output))
      end
      assert_match(/generator returned/, error.message)
    end
  end

  def test_prompt_bounds_patches_before_metadata_and_marks_omissions
    patch = "x" * (Prdigest::Document::MAX_PROMPT_BYTES * 2)
    facts = facts_with(patches: [{ "path" => "lib/change.rb", "patch" => patch, "truncated" => false, "omitted" => false }])

    payload = prompt_payload(facts)

    assert_operator JSON.generate(payload).bytesize, :<=, Prdigest::Document::MAX_PROMPT_BYTES
    rendered_patch = payload.dig("digest", "repositories", 0, "pull_requests", 0, "patches", 0)
    assert_equal true, rendered_patch.fetch("truncated")
    assert_operator rendered_patch.fetch("patch").length, :<, patch.length
  end

  def test_prompt_fails_when_titles_and_descriptions_alone_exceed_the_limit
    facts = facts_with(description: "d" * Prdigest::Document::MAX_PROMPT_BYTES)

    error = assert_raises(Prdigest::GenerationError) { Prdigest::Document.prompt(facts) }

    assert_match(/metadata exceeds/, error.message)
  end

  private

  def facts_with(description: "", patches: [])
    {
      "schema" => "prdigest-facts",
      "digest" => { "repositories" => [{ "name" => "owner/repo", "pull_requests" => [{
        "number" => 1, "title" => "Title", "url" => "https://example.test/pr/1",
        "description" => description, "patches" => patches, "patches_omitted" => 0
      }] }] }
    }
  end

  def prompt_payload(facts)
    Prdigest::Document.prompt(facts)[/<prdigest_facts>\n(.*)\n<\/prdigest_facts>/m, 1].then { |json| JSON.parse(json) }
  end
end
