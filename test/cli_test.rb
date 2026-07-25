# frozen_string_literal: true

require_relative "test_helper"
require "stringio"
require "tmpdir"
require "yaml"

class CliTest < Minitest::Test
  def test_exposes_thor_tasks_and_help_switches
    %w[facts run_cmd serve version].each { |command| assert_includes Prdigest::CLI.tasks.keys, command }
    assert_equal :run_cmd, Prdigest::CLI.send(:map).fetch("run")

    [["help"], ["--help"], ["-h"]].each do |argv|
      out = StringIO.new
      assert_equal 0, Prdigest::CLI.invoke(argv, out: out, err: StringIO.new)
      assert_match(/Usage: prdigest run/, out.string)
      assert_match(/prdigest facts/, out.string)
    end
  end

  def test_facts_emits_one_json_document_with_explicit_scope_and_no_telegram_token
    path = write_config(include_telegram: false)
    captured = nil
    document = {
      schema: "prdigest-facts",
      schema_version: 1,
      status: "success",
      error: nil,
      digest: { date: "2026-01-15" }
    }
    factory = lambda do |**options|
      captured = options
      Struct.new(:document) { def call = document }.new(document)
    end
    out = StringIO.new
    err = StringIO.new

    code = Prdigest::CLI.invoke(
      [
        "facts", "--config", path, "--date", "2026-01-15",
        "--repo", "Owner/One", "--repo=other/two", "--repo", "owner/one"
      ],
      out: out,
      err: err,
      env: { "GITHUB_TOKEN" => "synthetic" },
      facts_runner_factory: factory
    )

    assert_equal 0, code
    assert_equal JSON.parse(JSON.generate(document)), JSON.parse(out.string)
    assert_equal 1, out.string.lines.length
    assert_empty err.string
    assert_equal "2026-01-15", captured.fetch(:date)
    assert_equal ["Owner/One", "other/two"], captured.fetch(:repositories)
    assert_equal "Europe/London", captured.fetch(:config).timezone
  end

  def test_facts_requires_only_the_github_token
    path = write_config(include_telegram: false)
    out = StringIO.new

    code = Prdigest::CLI.invoke(
      ["facts", "--config", path],
      out: out,
      err: StringIO.new,
      env: {},
      facts_runner_factory: ->(**) { flunk "facts runner must not start" }
    )

    assert_equal 2, code
    assert_equal(
      {
        "schema" => "prdigest-facts",
        "schema_version" => 1,
        "status" => "failure",
        "error" => { "kind" => "config", "message" => "GitHub token is missing" },
        "digest" => nil
      },
      JSON.parse(out.string)
    )
  end

  def test_facts_rejects_run_only_options_and_uses_its_json_failure_contract
    path = write_config(include_telegram: false)

    [["--dry-run"], ["--json"], ["--help"], ["--date", "2026-1-1"]].each do |arguments|
      out = StringIO.new
      code = Prdigest::CLI.invoke(
        ["facts", "--config", path, *arguments],
        out: out,
        err: StringIO.new,
        env: { "GITHUB_TOKEN" => "synthetic" },
        facts_runner_factory: ->(**) { flunk "facts runner must not start" }
      )

      assert_equal 2, code
      payload = JSON.parse(out.string)
      assert_equal "prdigest-facts", payload.fetch("schema")
      assert_equal "failure", payload.fetch("status")
      assert_includes %w[cli config], payload.dig("error", "kind")
    end
  end

  def test_facts_reports_fetch_and_internal_failures_without_partial_output
    path = write_config(include_telegram: false)
    failures = [
      [Prdigest::FetchError.new("GitHub fetch failed safely", kind: "github"), 3, "github", "GitHub fetch failed safely"],
      [RuntimeError.new("must not escape"), 1, "internal", "unexpected facts failure (RuntimeError)"]
    ]

    failures.each do |failure, expected_code, expected_kind, expected_message|
      out = StringIO.new
      err = StringIO.new
      runner = Object.new
      runner.define_singleton_method(:call) { raise failure }

      code = Prdigest::CLI.invoke(
        ["facts", "--config", path],
        out: out,
        err: err,
        env: { "GITHUB_TOKEN" => "synthetic" },
        facts_runner_factory: ->(**) { runner }
      )

      assert_equal expected_code, code
      assert_equal 1, out.string.lines.length
      assert_empty err.string
      payload = JSON.parse(out.string)
      assert_equal "failure", payload.fetch("status")
      assert_equal expected_kind, payload.dig("error", "kind")
      assert_equal expected_message, payload.dig("error", "message")
      refute_includes out.string, "must not escape"
    end
  end

  def test_config_discovery_precedence
    Dir.mktmpdir do |dir|
      explicit = File.join(dir, "explicit.yml")
      env_path = File.join(dir, "env.yml")
      system = File.join(dir, "system.yml")
      [explicit, env_path, system].each { |path| File.write(path, "--- {}\n") }
      env = { "PRDIGEST_CONFIG" => env_path }
      assert_equal explicit, Prdigest::Config.resolve_path(explicit: explicit, env: env, system_path: system)
      assert_equal env_path, Prdigest::Config.resolve_path(env: env, system_path: system)
      assert_equal system, Prdigest::Config.resolve_path(env: {}, system_path: system)
      File.unlink(system)
      assert_raises(Prdigest::ConfigError) { Prdigest::Config.resolve_path(env: {}, system_path: system) }
    end
  end

  def test_unknown_command_json_is_one_complete_refusal
    out = StringIO.new
    err = StringIO.new
    code = Prdigest::CLI.invoke(["wat", "--json"], out: out, err: err)
    assert_equal 2, code
    payload = JSON.parse(out.string)
    assert_equal "failure", payload["status"]
    assert_equal "cli", payload.dig("error", "kind")
    assert_empty err.string
  end

  def test_dry_run_requires_github_but_not_telegram_token
    path = write_config
    out = StringIO.new
    code = Prdigest::CLI.invoke(
      ["run", "--config", path, "--dry-run", "--json"], out: out, err: StringIO.new,
      env: {}, runner_factory: ->(**) { flunk "runner must not start" }
    )
    assert_equal 2, code
    assert_equal "config", JSON.parse(out.string).dig("error", "kind")

    result = Prdigest::Result.new(status: "dry_run", mode: "scheduled", requested_days: [Date.new(2026, 1, 1)], chunks: ["preview"])
    factory = ->(**) { Struct.new(:result) { def call = result }.new(result) }
    out = StringIO.new
    code = Prdigest::CLI.invoke(
      ["run", "--config=#{path}", "--dry-run", "--json"], out: out, err: StringIO.new,
      env: { "GITHUB_TOKEN" => "synthetic" }, runner_factory: factory
    )
    assert_equal 0, code
    assert_equal "dry_run", JSON.parse(out.string)["status"]
  end

  def test_repeatable_repo_flags_override_config_for_embedding_callers
    path = write_config
    captured = nil
    result = Prdigest::Result.new(
      status: "dry_run",
      mode: "explicit_date_replay",
      requested_days: [Date.new(2026, 1, 1)],
      chunks: ["preview"]
    )
    factory = lambda do |**options|
      captured = options
      Struct.new(:result) { def call = result }.new(result)
    end

    out = StringIO.new
    code = Prdigest::CLI.invoke(
      [
        "run", "--config", path, "--date", "2026-01-01", "--dry-run", "--json",
        "--repo", "Owner/One", "--repo=other/two", "--repo", "owner/one"
      ],
      out: out,
      err: StringIO.new,
      env: { "GITHUB_TOKEN" => "synthetic" },
      runner_factory: factory
    )

    assert_equal 0, code
    assert_equal ["Owner/One", "other/two"], captured.fetch(:repositories)
    assert_equal "prdigest-result", JSON.parse(out.string).fetch("schema")
  end

  def test_repo_flags_reject_malformed_repository_names
    path = write_config
    out = StringIO.new

    code = Prdigest::CLI.invoke(
      ["run", "--config", path, "--dry-run", "--json", "--repo", "../escape"],
      out: out,
      err: StringIO.new,
      env: { "GITHUB_TOKEN" => "synthetic" },
      runner_factory: ->(**) { flunk "runner must not start" }
    )

    assert_equal 2, code
    assert_equal "config", JSON.parse(out.string).dig("error", "kind")
  end

  def test_real_send_requires_telegram_token_and_date_is_strict
    path = write_config
    env = { "GITHUB_TOKEN" => "synthetic" }
    [["run", "--config", path, "--json"], ["run", "--config", path, "--date", "2026-1-1", "--json"]].each do |argv|
      out = StringIO.new
      assert_equal 2, Prdigest::CLI.invoke(argv, out: out, err: StringIO.new, env: env)
      assert_equal "config", JSON.parse(out.string).dig("error", "kind")
    end
  end

  def test_human_failure_reports_progress_and_error
    path = write_config
    result = Prdigest::Result.failure(
      mode: "scheduled",
      error_kind: "github",
      message: "synthetic failure",
      requested_days: [Date.new(2026, 1, 1), Date.new(2026, 1, 2), Date.new(2026, 1, 3)],
      settled_days: [Date.new(2026, 1, 1)],
      skipped_days: [Date.new(2025, 12, 31)],
      failed_date: Date.new(2026, 1, 2),
      remaining_days: [Date.new(2026, 1, 2), Date.new(2026, 1, 3)]
    )
    factory = ->(**) { Struct.new(:result) { def call = result }.new(result) }
    out = StringIO.new
    err = StringIO.new

    code = Prdigest::CLI.invoke(
      ["run", "--config", path],
      out: out,
      err: err,
      env: { "GITHUB_TOKEN" => "synthetic", "TELEGRAM_BOT_TOKEN" => "synthetic" },
      runner_factory: factory
    )

    assert_equal 6, code
    assert_empty out.string
    assert_includes err.string, "settled=2026-01-01"
    assert_includes err.string, "skipped=2025-12-31"
    assert_includes err.string, "remaining=2026-01-02,2026-01-03"
    assert_includes err.string, "github: synthetic failure"
  end

  private

  def write_config(include_telegram: true)
    path = File.join(Dir.mktmpdir, "config.yml")
    raw = {
      "timezone" => include_telegram ? "UTC" : "Europe/London",
      "github" => { "repos" => ["o/r"] }
    }
    raw["telegram"] = { "chat_id" => 1, "chat_id_allowlist" => [1] } if include_telegram
    File.write(path, YAML.dump(raw))
    path
  end
end
