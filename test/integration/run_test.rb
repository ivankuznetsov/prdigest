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

  def test_facts_runs_real_read_only_layers_without_telegram_configuration
    Dir.mktmpdir do |dir|
      config_path = File.join(dir, "config.yml")
      File.write(config_path, YAML.dump(
        "timezone" => "UTC",
        "github" => { "repos" => ["example/project"] },
        "digest" => { "line_stats" => false }
      ))
      stub_request(:get, %r{https://api.github.com/search/issues}).to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: JSON.generate(total_count: 0, incomplete_results: false, items: [])
      )
      out = StringIO.new
      forbidden = ->(*) { flunk "facts must not construct delivery or presentation layers" }

      Prdigest::State.stub(:new, forbidden) do
        Prdigest::Telegram.stub(:new, forbidden) do
          Prdigest::DeliveryCheckpointStore.stub(:new, forbidden) do
            Prdigest::Renderer.stub(:new, forbidden) do
              code = Prdigest::CLI.invoke(
                ["facts", "--config", config_path, "--date", "2026-01-15"],
                out: out,
                err: StringIO.new,
                env: { "GITHUB_TOKEN" => "synthetic-token" }
              )
              payload = JSON.parse(out.string)

              assert_equal 0, code
              assert_equal "prdigest-facts", payload.fetch("schema")
              assert_equal "success", payload.fetch("status")
              assert_equal "2026-01-15", payload.dig("digest", "date")
              assert_equal ["example/project"], payload.dig("digest", "repository_order")
            end
          end
        end
      end
    end
  end

  def test_prose_runs_real_read_only_layers_and_writes_raw_provider_text
    Dir.mktmpdir do |dir|
      config_path = File.join(dir, "config.yml")
      File.write(config_path, YAML.dump(
        "timezone" => "UTC",
        "github" => { "repos" => ["example/project"] },
        "prose" => {
          "provider" => "openai_compatible",
          "base_url" => "https://provider.example/v1",
          "model" => "example/model",
          "api_key_env" => "PROVIDER_KEY"
        },
        "digest" => { "line_stats" => false }
      ))
      stub_request(:get, %r{https://api.github.com/search/issues}).to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: JSON.generate(total_count: 0, incomplete_results: false, items: [])
      )
      provider = stub_request(:post, "https://provider.example/v1/chat/completions").to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: JSON.generate(choices: [{ message: { content: "Raw <digest> & summary" } }])
      )
      out = StringIO.new
      err = StringIO.new

      forbidden = ->(*) { flunk "stdout prose must not construct delivery dependencies" }
      Prdigest::Telegram.stub(:new, forbidden) do
        Prdigest::DeliveryCheckpointStore.stub(:new, forbidden) do
          code = Prdigest::CLI.invoke(
            ["prose", "--config", config_path, "--date", "2026-01-15"],
            out: out,
            err: err,
            env: {
              "GITHUB_TOKEN" => "synthetic-github",
              "PROVIDER_KEY" => "synthetic-provider"
            }
          )

          assert_equal 0, code
          assert_equal "Raw <digest> & summary\n", out.string
          assert_empty err.string
          assert_requested provider, times: 1
        end
      end
    end
  end

  def test_prose_delivery_resumes_stored_payload_without_generation_credentials
    Dir.mktmpdir do |dir|
      delivery_path = File.join(dir, "deliveries")
      config_path = File.join(dir, "config.yml")
      File.write(config_path, YAML.dump(
        "timezone" => "UTC",
        "github" => { "repos" => ["example/project"] },
        "telegram" => {
          "chat_id" => 1,
          "chat_id_allowlist" => [1]
        },
        "prose" => {
          "provider" => "openai_compatible",
          "base_url" => "https://provider.example/v1",
          "model" => "example/model",
          "api_key_env" => "PROVIDER_KEY"
        },
        "state" => { "delivery_path" => delivery_path },
        "digest" => { "line_stats" => false }
      ))
      store = Prdigest::DeliveryCheckpointStore.new(root: File.join(delivery_path, "prose"))
      store.with_checkpoint(
        date: Date.new(2026, 1, 15),
        chat_id: 1,
        scope: ["example/project"],
        chunks: ["Stored &amp; safe"]
      ) { }
      telegram = stub_request(:post, %r{https://api.telegram.org/bot[^/]+/sendMessage}).to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: JSON.generate(ok: true, result: {})
      )
      github = stub_request(:get, %r{https://api.github.com/})
      provider = stub_request(:post, "https://provider.example/v1/chat/completions")
      out = StringIO.new
      err = StringIO.new

      code = Prdigest::CLI.invoke(
        ["prose", "--config", config_path, "--date", "2026-01-15", "--deliver"],
        out: out,
        err: err,
        env: { "TELEGRAM_BOT_TOKEN" => "synthetic-telegram" }
      )

      assert_equal 0, code
      assert_equal "prdigest: prose delivered; date=2026-01-15 chunks=1\n", out.string
      assert_empty err.string
      assert_requested telegram, times: 1
      assert_not_requested github
      assert_not_requested provider
    end
  end
end
