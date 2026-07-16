# frozen_string_literal: true

require_relative "test_helper"
require "stringio"
require "tmpdir"
require "yaml"

class CliTest < Minitest::Test
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

  def test_real_send_requires_telegram_token_and_date_is_strict
    path = write_config
    env = { "GITHUB_TOKEN" => "synthetic" }
    [["run", "--config", path, "--json"], ["run", "--config", path, "--date", "2026-1-1", "--json"]].each do |argv|
      out = StringIO.new
      assert_equal 2, Prdigest::CLI.invoke(argv, out: out, err: StringIO.new, env: env)
      assert_equal "config", JSON.parse(out.string).dig("error", "kind")
    end
  end

  private

  def write_config
    path = File.join(Dir.mktmpdir, "config.yml")
    File.write(path, YAML.dump(
      "timezone" => "UTC", "github" => { "repos" => ["o/r"] },
      "telegram" => { "chat_id" => 1, "chat_id_allowlist" => [1] }
    ))
    path
  end
end
