# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "yaml"

class ConfigTest < Minitest::Test
  def test_rejects_empty_repos
    path = write_config("github" => { "repos" => [] }, "telegram" => {
      "chat_id" => -1001,
      "chat_id_allowlist" => [-1001]
    })
    err = assert_raises(Prdigest::ConfigError) { Prdigest::Config.load(path) }
    assert_match(/repos/, err.message)
  end

  def test_requires_chat_in_allowlist
    path = write_config(
      "github" => { "repos" => ["o/r"] },
      "telegram" => { "chat_id" => 1, "chat_id_allowlist" => [2] }
    )
    err = assert_raises(Prdigest::ConfigError) { Prdigest::Config.load(path) }
    assert_match(/allowlist/, err.message)
  end

  def test_loads_valid_config
    path = write_config(
      "timezone" => "Europe/London",
      "github" => { "repos" => ["ivankuznetsov/hive"] },
      "telegram" => { "chat_id" => -1001, "chat_id_allowlist" => [-1001] }
    )
    cfg = Prdigest::Config.load(path)
    assert_equal ["ivankuznetsov/hive"], cfg.repos
    assert_equal(-1001, Integer(cfg.chat_id))
    assert_equal 7, cfg.max_catchup_days
    assert_equal File.expand_path("~/.local/share/prdigest/deliveries"), cfg.delivery_state_path
  end

  def test_delivery_state_defaults_next_to_cursor_and_can_be_overridden
    path = write_config(
      "github" => { "repos" => ["o/r"] },
      "telegram" => { "chat_id" => 1, "chat_id_allowlist" => [1] },
      "state" => { "path" => "/var/lib/prdigest/cursor.json" }
    )
    assert_equal "/var/lib/prdigest/deliveries", Prdigest::Config.load(path).delivery_state_path

    raw = YAML.safe_load_file(path)
    raw["state"]["delivery_path"] = "/run/prdigest/delivery"
    assert_equal "/run/prdigest/delivery", Prdigest::Config.new(raw).delivery_state_path
  end

  def test_validates_timezone_cap_and_repository_shape
    base = {
      "github" => { "repos" => ["owner/repo"] },
      "telegram" => { "chat_id" => 1, "chat_id_allowlist" => [1, 2] }
    }

    [0, 31].each do |cap|
      path = write_config(base.merge("schedule" => { "max_catchup_days" => cap }))
      assert_raises(Prdigest::ConfigError) { Prdigest::Config.load(path) }
    end

    path = write_config(base.merge("timezone" => "Mars/Olympus_Mons"))
    assert_raises(Prdigest::ConfigError) { Prdigest::Config.load(path) }

    path = write_config(base.merge("github" => { "repos" => ["not-a-repo"] }))
    assert_raises(Prdigest::ConfigError) { Prdigest::Config.load(path) }
  end

  def test_accepts_cap_boundaries_and_extra_allowlisted_chats
    [1, 30].each do |cap|
      path = write_config(
        "timezone" => "UTC",
        "schedule" => { "max_catchup_days" => cap },
        "github" => { "repos" => ["o/r"] },
        "telegram" => { "chat_id" => 2, "chat_id_allowlist" => [1, 2] }
      )
      assert_equal cap, Prdigest::Config.load(path).max_catchup_days
    end
  end

  def test_facts_capability_does_not_require_telegram_configuration
    path = write_config(
      "timezone" => "Europe/London",
      "schedule" => { "max_catchup_days" => 14 },
      "github" => { "repos" => ["owner/repo"] }
    )

    config = Prdigest::Config.load(path, capability: :facts)

    assert_equal "Europe/London", config.timezone
    assert_equal 14, config.max_catchup_days
    assert_equal ["owner/repo"], config.repos
  end

  def test_facts_capability_still_validates_timezone_schedule_and_repositories
    configurations = [
      {
        "timezone" => "Mars/Olympus_Mons",
        "github" => { "repos" => ["owner/repo"] }
      },
      {
        "schedule" => { "max_catchup_days" => 31 },
        "github" => { "repos" => ["owner/repo"] }
      },
      {
        "github" => { "repos" => ["not-a-repository"] }
      }
    ]

    configurations.each do |raw|
      assert_raises(Prdigest::ConfigError) do
        Prdigest::Config.load(write_config(raw), capability: :facts)
      end
    end
  end

  def test_default_load_capability_remains_telegram_strict
    path = write_config(
      "timezone" => "UTC",
      "github" => { "repos" => ["owner/repo"] }
    )

    error = assert_raises(Prdigest::ConfigError) { Prdigest::Config.load(path) }

    assert_equal "telegram.chat_id is required", error.message
  end

  def test_prose_capability_requires_only_github_and_openai_compatible_provider
    path = write_config(
      "timezone" => "Europe/London",
      "github" => { "repos" => ["owner/repo"] },
      "prose" => {
        "provider" => "openai_compatible",
        "base_url" => "https://openrouter.ai/api/v1/",
        "model" => "provider/model",
        "api_key_env" => "OPENROUTER_API_KEY"
      }
    )

    config = Prdigest::Config.load(path, capability: :prose)

    assert_equal "openai_compatible", config.prose_provider
    assert_equal "https://openrouter.ai/api/v1/", config.prose_base_url
    assert_equal "provider/model", config.prose_model
    assert_equal "OPENROUTER_API_KEY", config.prose_api_key_env
    assert_equal "env-secret", config.prose_api_key("OPENROUTER_API_KEY" => "env-secret")
    assert_nil config.chat_id
  end

  def test_prose_delivery_additionally_requires_allowlisted_telegram
    raw = {
      "github" => { "repos" => ["owner/repo"] },
      "prose" => valid_prose
    }
    error = assert_raises(Prdigest::ConfigError) do
      Prdigest::Config.load(write_config(raw), capability: :prose_delivery)
    end
    assert_equal "telegram.chat_id is required", error.message

    raw["telegram"] = { "chat_id" => 1, "chat_id_allowlist" => [1] }
    config = Prdigest::Config.load(write_config(raw), capability: :prose_delivery)
    assert_equal 1, config.chat_id
  end

  def test_prose_scope_rejects_invalid_provider_settings_and_inline_secrets
    invalid = [
      [{}, /prose.provider/],
      [valid_prose.merge("provider" => "openrouter"), /prose.provider/],
      [valid_prose.merge("base_url" => "provider.example/v1"), /prose.base_url/],
      [valid_prose.merge("base_url" => "ftp://provider.example/v1"), /prose.base_url/],
      [valid_prose.merge("base_url" => "https://user:pass@provider.example/v1"), /prose.base_url/],
      [valid_prose.merge("base_url" => "https://provider.example/v1?secret=yes"), /prose.base_url/],
      [valid_prose.merge("base_url" => "https://provider.example/v1#fragment"), /prose.base_url/],
      [valid_prose.merge("model" => "  "), /prose.model/],
      [valid_prose.merge("api_key_env" => "1-BAD"), /prose.api_key_env/],
      [valid_prose.merge("api_key" => "inline-secret"), /environment variable/]
    ]

    invalid.each do |prose, expected|
      error = assert_raises(Prdigest::ConfigError) do
        Prdigest::Config.load(
          write_config("github" => { "repos" => ["owner/repo"] }, "prose" => prose),
          capability: :prose
        )
      end
      assert_match expected, error.message
      refute_includes error.message, "inline-secret"
    end
  end

  def test_http_base_url_is_valid_only_for_strict_loopback_endpoints
    [
      "http://localhost:11434/v1",
      "http://127.0.0.1:11434/v1",
      "http://127.255.255.255:11434/v1",
      "http://[::1]:11434/v1"
    ].each do |base_url|
      path = write_config(
        "github" => { "repos" => ["owner/repo"] },
        "prose" => valid_prose.merge("base_url" => base_url)
      )

      assert_equal base_url, Prdigest::Config.load(path, capability: :prose).prose_base_url
    end
  end

  def test_http_base_url_rejects_remote_and_loopback_lookalike_hosts
    [
      "http://provider.example/v1",
      "http://localhost.example/v1",
      "http://127.0.0.1.example/v1",
      "http://[::ffff:127.0.0.1]/v1"
    ].each do |base_url|
      path = write_config(
        "github" => { "repos" => ["owner/repo"] },
        "prose" => valid_prose.merge("base_url" => base_url)
      )

      error = assert_raises(Prdigest::ConfigError) do
        Prdigest::Config.load(path, capability: :prose)
      end
      assert_match(/prose.base_url/, error.message)
    end
  end

  def test_run_and_facts_do_not_validate_unselected_prose_configuration
    invalid_prose = { "provider" => "not-supported", "api_key" => "inline-secret" }
    facts_path = write_config(
      "github" => { "repos" => ["owner/repo"] },
      "prose" => invalid_prose
    )
    assert_equal ["owner/repo"], Prdigest::Config.load(facts_path, capability: :facts).repos

    run_path = write_config(
      "github" => { "repos" => ["owner/repo"] },
      "telegram" => { "chat_id" => 1, "chat_id_allowlist" => [1] },
      "prose" => invalid_prose
    )
    assert_equal 1, Prdigest::Config.load(run_path).chat_id
  end

  private

  def valid_prose
    {
      "provider" => "openai_compatible",
      "base_url" => "https://provider.example/v1",
      "model" => "provider/model",
      "api_key_env" => "PROVIDER_API_KEY"
    }
  end

  def write_config(hash)
    path = File.join(Dir.mktmpdir, "config.yml")
    File.write(path, YAML.dump(hash))
    path
  end
end
