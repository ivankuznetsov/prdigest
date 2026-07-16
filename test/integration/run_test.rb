# frozen_string_literal: true

require_relative "../test_helper"
require "stringio"
require "tmpdir"
require "yaml"

class RunIntegrationTest < Minitest::Test
  def test_real_layers_complete_offline_dry_run
    Dir.mktmpdir do |dir|
      config_path = File.join(dir, "config.yml")
      File.write(config_path, YAML.dump(
        "timezone" => "UTC",
        "github" => { "repos" => ["example/project"] },
        "telegram" => { "chat_id" => 1, "chat_id_allowlist" => [1] },
        "digest" => { "line_stats" => false, "send_empty" => true, "empty_message" => "No merges for {date}" }
      ))
      stub_request(:get, %r{https://api.github.com/search/issues}).to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: JSON.generate(total_count: 0, incomplete_results: false, items: [])
      )
      out = StringIO.new
      code = Prdigest::CLI.invoke(
        ["run", "--config", config_path, "--date", "2026-01-15", "--dry-run", "--json"],
        out: out, err: StringIO.new, env: { "GITHUB_TOKEN" => "synthetic-token" }
      )
      payload = JSON.parse(out.string)
      assert_equal 0, code
      assert_equal "dry_run", payload["status"]
      assert_equal ["2026-01-15"], payload["requested_days"]
      assert_equal ["No merges for 2026-01-15"], payload["chunks"]
    end
  end
end
