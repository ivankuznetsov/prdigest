# frozen_string_literal: true

require_relative "test_helper"
require "yaml"

class OpenclawSkillTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  SKILL_ROOT = File.join(ROOT, "openclaw", "skills", "prdigest")
  SKILL_PATH = File.join(SKILL_ROOT, "SKILL.md")

  def test_bundle_is_a_single_clawhub_skill_without_an_embedded_runtime
    files = Dir.glob("**/*", base: SKILL_ROOT).select do |path|
      File.file?(File.join(SKILL_ROOT, path))
    end
    assert_equal ["SKILL.md"], files
  end

  def test_frontmatter_is_installable_without_making_a_release_version_decision
    metadata, = read_skill

    assert_equal "prdigest", metadata.fetch("name")
    assert_equal true, metadata.fetch("user-invocable")
    assert_match(/pull request/i, metadata.fetch("description"))
    refute metadata.key?("version")

    openclaw = metadata.dig("metadata", "openclaw")
    assert_equal "https://github.com/ivankuznetsov/prdigest", openclaw.fetch("homepage")
    assert_equal true, openclaw.fetch("always")
    refute openclaw.key?("install")
    refute openclaw.key?("requires")
  end

  def test_skill_uses_only_the_deterministic_facts_contract
    _, body = read_skill

    assert_includes body, "command -v prdigest"
    assert_match(/ask.*before.*install/i, body)
    assert_includes body, "prdigest facts"
    assert_includes body, "schema"
    assert_includes body, "prdigest-facts"
    assert_includes body, "schema_version"
    assert_match(/status.*success/i, body)
    assert_match(/untrusted data/i, body)
    assert_match(/never instructions/i, body)
    assert_match(/never fabricate/i, body)

    shell_commands = body.scan(/```sh\n(.*?)```/m).join("\n")
    refute_match(/\bprdigest (?:run|prose)\b/, shell_commands)
    refute_match(/(?:^|\s)(?:gh|curl)\s/m, shell_commands)
  end

  def test_skill_forbids_second_fetch_delivery_provider_and_secret_output
    _, body = read_skill

    assert_match(/no second GitHub query/i, body)
    assert_match(/do not.*Telegram/i, body)
    assert_match(/do not.*provider/i, body)
    assert_match(/(?:do not|never).*credentials/i, body)
    assert_match(/do not.*fallback/i, body)
    assert_match(/separately quoted/i, body)
  end

  private

  def read_skill
    contents = File.read(SKILL_PATH)
    match = contents.match(/\A---\n(.*?)\n---\n(.*)\z/m)
    refute_nil match, "SKILL.md must contain YAML frontmatter"

    [YAML.safe_load(match[1], aliases: false), match[2]]
  end
end
