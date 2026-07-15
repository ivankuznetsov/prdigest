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
  end

  private

  def write_config(hash)
    path = File.join(Dir.mktmpdir, "config.yml")
    File.write(path, YAML.dump(hash))
    path
  end
end
