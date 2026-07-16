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

  private

  def write_config(hash)
    path = File.join(Dir.mktmpdir, "config.yml")
    File.write(path, YAML.dump(hash))
    path
  end
end
