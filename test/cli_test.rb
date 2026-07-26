# frozen_string_literal: true

require_relative "test_helper"
require "stringio"
require "tmpdir"
require "yaml"

class CliTest < Minitest::Test
  def test_exposes_thor_tasks_and_help_switches
    assert_equal %w[facts prose version], Prdigest::CLI.tasks.keys.sort
    refute_includes Prdigest::CLI.send(:map), "run"

    [["help"], ["--help"], ["-h"]].each do |argv|
      out = StringIO.new
      assert_equal 0, Prdigest::CLI.invoke(argv, out: out, err: StringIO.new)
      assert_match(/prdigest facts/, out.string)
      assert_match(/prdigest prose/, out.string)
      refute_match(/prdigest run/, out.string)
      refute_match(/prdigest serve/, out.string)
    end
  end

  def test_removed_delivery_commands_are_unknown
    %w[run serve].each do |command|
      out = StringIO.new
      err = StringIO.new

      code = Prdigest::CLI.invoke([command], out: out, err: err)

      assert_equal 2, code
      assert_empty out.string
      assert_equal "prdigest: cli: unknown command\n", err.string
    end
  end

  def test_prose_stdout_emits_exact_raw_text_with_one_terminal_newline
    path = write_prose_config(include_telegram: false)
    captured = nil
    outcome = Struct.new(:date, :prose, :delivery) {
      def delivered? = !delivery.nil?
    }.new(Date.new(2026, 1, 15), "First line\nSecond line\n\n", nil)
    factory = lambda do |**options|
      captured = options
      Struct.new(:outcome) { def call = outcome }.new(outcome)
    end
    out = StringIO.new
    err = StringIO.new

    code = Prdigest::CLI.invoke(
      [
        "prose", "--config", path, "--date", "2026-01-15",
        "--repo", "Owner/One", "--repo=other/two"
      ],
      out: out,
      err: err,
      env: { "GITHUB_TOKEN" => "github", "PROVIDER_KEY" => "provider" },
      prose_runner_factory: factory
    )

    assert_equal 0, code
    assert_equal "First line\nSecond line\n", out.string
    assert_empty err.string
    assert_equal false, captured.fetch(:deliver)
    assert_equal ["Owner/One", "other/two"], captured.fetch(:repositories)
  end

  def test_prose_delivery_requires_only_telegram_credentials_before_runner
    path = write_prose_config
    captured = nil
    outcome = Struct.new(:date, :prose, :delivery) {
      def delivered? = !delivery.nil?
    }.new(
      Date.new(2026, 1, 15),
      nil,
      { accepted_chunks: 2, total_chunks: 2, status: "completed" }
    )
    factory = lambda do |**options|
      captured = options
      Struct.new(:outcome) { def call = outcome }.new(outcome)
    end
    out = StringIO.new
    err = StringIO.new

    code = Prdigest::CLI.invoke(
      ["prose", "--config", path, "--date", "2026-01-15", "--deliver"],
      out: out,
      err: err,
      env: { "TELEGRAM_BOT_TOKEN" => "telegram" },
      prose_runner_factory: factory
    )

    assert_equal 0, code
    assert_equal "prdigest: prose delivered; date=2026-01-15 chunks=2\n", out.string
    assert_empty err.string
    assert_equal true, captured.fetch(:deliver)
  end

  def test_prose_stdout_requires_github_and_provider_credentials_without_starting_runner
    path = write_prose_config(include_telegram: false)
    [
      [{ "PROVIDER_KEY" => "provider" }, "GitHub token is missing"],
      [{ "GITHUB_TOKEN" => "github" }, "prose API key environment variable is unset"]
    ].each do |env, message|
      out = StringIO.new
      err = StringIO.new

      code = Prdigest::CLI.invoke(
        ["prose", "--config", path],
        out: out,
        err: err,
        env: env,
        prose_runner_factory: ->(**) { flunk "prose runner must not start" }
      )

      assert_equal 2, code
      assert_empty out.string
      assert_includes err.string, message
    end
  end

  def test_prose_delivery_requires_telegram_but_defers_generation_credentials
    path = write_prose_config
    out = StringIO.new
    err = StringIO.new

    code = Prdigest::CLI.invoke(
      ["prose", "--config", path, "--deliver"],
      out: out,
      err: err,
      env: {},
      prose_runner_factory: ->(**) { flunk "runner must not start without Telegram" }
    )

    assert_equal 2, code
    assert_empty out.string
    assert_includes err.string, "Telegram bot token is missing"
  end

  def test_prose_rejects_incompatible_options_and_deliver_is_prose_only
    path = write_prose_config

    %w[--dry-run --json].each do |option|
      out = StringIO.new
      err = StringIO.new
      code = Prdigest::CLI.invoke(
        ["prose", "--config", path, option],
        out: out,
        err: err,
        env: credentials,
        prose_runner_factory: ->(**) { flunk "prose runner must not start" }
      )
      assert_equal 2, code
      assert_empty out.string
      assert_includes err.string, "#{option} is not valid for prose"
    end

    facts_out = StringIO.new
    code = Prdigest::CLI.invoke(
      ["facts", "--config", path, "--deliver"],
      out: facts_out,
      err: StringIO.new,
      env: credentials,
      facts_runner_factory: ->(**) { flunk "facts runner must not start" }
    )
    assert_equal 2, code
    assert_equal "cli", JSON.parse(facts_out.string).dig("error", "kind")

    [["version", "--deliver"], ["help", "--deliver"]].each do |argv|
      out = StringIO.new
      err = StringIO.new
      assert_equal 2, Prdigest::CLI.invoke(argv, out: out, err: err)
      assert_empty out.string
      assert_includes err.string, "--deliver is only valid for prose"
    end
  end

  def test_prose_maps_typed_failures_without_writing_stdout_or_secrets
    path = write_prose_config
    secret = "provider-secret"
    cases = [
      [Prdigest::FetchError.new("GitHub unavailable", kind: "github"), 3, "github"],
      [Prdigest::SendError.new("Telegram unavailable", kind: "telegram"), 4, "telegram"],
      [Prdigest::StateError.new("checkpoint unavailable"), 5, "state"],
      [Prdigest::GenerationError.new("provider unavailable", kind: "provider"), 7, "provider"],
      [Prdigest::GenerationError.new("provider uncertain", kind: "provider_ambiguous"), 7, "provider_ambiguous"],
      [Prdigest::RenderError.new("blank prose", kind: "prose_render"), 1, "prose_render"],
      [RuntimeError.new("internal #{secret} details"), 1, "internal"]
    ]

    cases.each do |failure, expected_code, expected_kind|
      runner = Object.new
      runner.define_singleton_method(:call) { raise failure }
      out = StringIO.new
      err = StringIO.new

      code = Prdigest::CLI.invoke(
        ["prose", "--config", path, "--deliver"],
        out: out,
        err: err,
        env: {
          "TELEGRAM_BOT_TOKEN" => "telegram-secret",
          "GITHUB_TOKEN" => "github-secret",
          "PROVIDER_KEY" => secret
        },
        prose_runner_factory: ->(**) { runner }
      )

      assert_equal expected_code, code
      assert_empty out.string
      assert_includes err.string, "prdigest: #{expected_kind}:"
      refute_includes err.string, secret
      refute_includes err.string, "internal #{secret} details"
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

  def test_unknown_command_is_a_cli_refusal
    out = StringIO.new
    err = StringIO.new
    code = Prdigest::CLI.invoke(["wat", "--json"], out: out, err: err)
    assert_equal 2, code
    assert_empty out.string
    assert_equal "prdigest: cli: unknown command\n", err.string
  end

  private

  def credentials
    {
      "GITHUB_TOKEN" => "github",
      "PROVIDER_KEY" => "provider",
      "TELEGRAM_BOT_TOKEN" => "telegram"
    }
  end

  def write_prose_config(include_telegram: true)
    path = File.join(Dir.mktmpdir, "config.yml")
    raw = {
      "timezone" => "UTC",
      "github" => {
        "repos" => ["o/r"],
        "token_env" => "GITHUB_TOKEN"
      },
      "prose" => {
        "provider" => "openai_compatible",
        "base_url" => "https://provider.example/v1",
        "model" => "example/model",
        "api_key_env" => "PROVIDER_KEY"
      }
    }
    if include_telegram
      raw["telegram"] = {
        "token_env" => "TELEGRAM_BOT_TOKEN",
        "chat_id" => 1,
        "chat_id_allowlist" => [1]
      }
    end
    File.write(path, YAML.dump(raw))
    path
  end

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
