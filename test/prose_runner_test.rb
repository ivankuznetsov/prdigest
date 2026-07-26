# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"

class ProseRunnerTest < Minitest::Test
  DATE = Date.new(2026, 7, 23)

  class FakeClock
    attr_reader :yesterday

    def initialize(yesterday: DATE)
      @yesterday = yesterday
    end

    def window(date)
      Prdigest::Clock::Window.new(
        date,
        Time.utc(date.year, date.month, date.day),
        Time.utc(date.year, date.month, date.day) + 86_400
      )
    end
  end

  class FakeGitHub
    attr_reader :calls

    def initialize
      @calls = []
    end

    def fetch(date:, window:, repositories:, line_stats:)
      @calls << {
        date: date,
        window: window,
        repositories: repositories,
        line_stats: line_stats
      }
      Prdigest::DayDigest.build(
        date: date,
        repository_order: repositories,
        pulls: [],
        line_stats: line_stats
      )
    end
  end

  class FakeGenerator
    attr_reader :facts

    def initialize(prose: "Raw <prose> & details", error: nil)
      @prose = prose
      @error = error
      @facts = []
    end

    def generate(document)
      @facts << document
      raise @error if @error

      @prose
    end
  end

  class FakeRenderer
    attr_reader :values

    def initialize(chunks: ["Rendered prose"])
      @chunks = chunks
      @values = []
    end

    def render(value)
      @values << value
      Prdigest::Renderer::Output.new(@chunks, "rendered")
    end
  end

  class CheckpointingTelegram
    attr_reader :network_sends

    def initialize
      @network_sends = []
    end

    def deliver(chunks = nil, digest_date:, checkpoint_store:, scope:, chunk_factory: nil)
      checkpoint_store.with_checkpoint(
        date: digest_date,
        chat_id: 1,
        scope: scope,
        chunks: chunks,
        chunk_factory: chunk_factory
      ) do |delivery|
        (delivery.next_chunk...delivery.chunks.length).each do |index|
          delivery.begin_attempt(index)
          @network_sends << delivery.chunks.fetch(index)
          delivery.accept(index)
        end
        delivery.delivery
      end
    end
  end

  def test_stdout_mode_returns_raw_prose_and_constructs_no_delivery_dependencies
    github = FakeGitHub.new
    generator = FakeGenerator.new
    renderer = FakeRenderer.new(chunks: ["escaped"])
    forbidden = -> { flunk "stdout mode must not construct delivery dependencies" }

    outcome = runner(
      github: github,
      generator: generator,
      renderer: renderer,
      telegram_factory: forbidden,
      checkpoint_store_factory: forbidden
    ).call

    assert_equal DATE, outcome.date
    assert_equal "Raw <prose> & details", outcome.prose
    assert_nil outcome.delivery
    refute outcome.delivered?
    assert_equal ["Raw <prose> & details"], renderer.values
    assert_equal "prdigest-facts", generator.facts.fetch(0).fetch(:schema)
    assert_equal DATE, github.calls.fetch(0).fetch(:date)
  end

  def test_delivery_replays_partial_checkpoint_without_github_provider_or_their_credentials
    Dir.mktmpdir do |root|
      config = config(delivery_path: root)
      checkpoint = Prdigest::DeliveryCheckpointStore.new(root: File.join(root, "prose"))
      checkpoint.with_checkpoint(
        date: DATE,
        chat_id: 1,
        scope: ["owner/repo"],
        chunks: ["stored one", "stored two"]
      ) do |delivery|
        delivery.begin_attempt(0)
        delivery.accept(0)
      end
      telegram = CheckpointingTelegram.new
      forbidden = ->(*) { flunk "stored checkpoint must bypass generation" }

      outcome = runner(
        config: config,
        deliver: true,
        env: { "TELEGRAM_BOT_TOKEN" => "telegram" },
        github: forbidden,
        generator: forbidden,
        telegram_factory: -> { telegram }
      ).call

      assert outcome.delivered?
      assert_nil outcome.prose
      assert_equal ["stored two"], telegram.network_sends
      assert_equal "completed", outcome.delivery.fetch(:status)
    end
  end

  def test_delivery_replays_completed_checkpoint_as_a_noop
    Dir.mktmpdir do |root|
      config = config(delivery_path: root)
      checkpoint = Prdigest::DeliveryCheckpointStore.new(root: File.join(root, "prose"))
      checkpoint.with_checkpoint(
        date: DATE,
        chat_id: 1,
        scope: ["owner/repo"],
        chunks: ["stored"]
      ) do |delivery|
        delivery.begin_attempt(0)
        delivery.accept(0)
      end
      telegram = CheckpointingTelegram.new
      forbidden = ->(*) { flunk "completed checkpoint must bypass generation" }

      outcome = runner(
        config: config,
        deliver: true,
        env: { "TELEGRAM_BOT_TOKEN" => "telegram" },
        github: forbidden,
        generator: forbidden,
        telegram_factory: -> { telegram }
      ).call

      assert outcome.delivered?
      assert_empty telegram.network_sends
      assert_equal "completed", outcome.delivery.fetch(:status)
    end
  end

  def test_provider_failure_sends_nothing_and_leaves_no_payload_checkpoint
    Dir.mktmpdir do |root|
      failure = Prdigest::GenerationError.new("provider unavailable")
      telegram = CheckpointingTelegram.new
      instance = runner(
        config: config(delivery_path: root),
        deliver: true,
        env: credentials,
        github: FakeGitHub.new,
        generator: FakeGenerator.new(error: failure),
        telegram_factory: -> { telegram }
      )

      error = assert_raises(Prdigest::GenerationError) { instance.call }

      assert_same failure, error
      assert_empty telegram.network_sends
      refute File.exist?(File.join(root, "prose", "#{DATE}.json"))
    end
  end

  def test_provider_control_characters_are_not_checkpointed_or_sent
    Dir.mktmpdir do |root|
      telegram = CheckpointingTelegram.new
      instance = runner(
        config: config(delivery_path: root),
        deliver: true,
        env: credentials,
        github: FakeGitHub.new,
        generator: FakeGenerator.new(prose: "\e]0;forged\aDigest"),
        renderer: Prdigest::ProseRenderer.new,
        telegram_factory: -> { telegram }
      )

      error = assert_raises(Prdigest::RenderError) { instance.call }

      assert_equal "prose_render", error.kind
      assert_empty telegram.network_sends
      refute File.exist?(File.join(root, "prose", "#{DATE}.json"))
    end
  end

  def test_fresh_delivery_checks_generation_credentials_before_network
    [
      [{ "PROVIDER_KEY" => "provider", "TELEGRAM_BOT_TOKEN" => "telegram" }, "GitHub token is missing"],
      [{ "GITHUB_TOKEN" => "github", "TELEGRAM_BOT_TOKEN" => "telegram" }, "prose API key environment variable is unset"]
    ].each do |env, message|
      Dir.mktmpdir do |root|
        github = FakeGitHub.new
        telegram = CheckpointingTelegram.new
        instance = runner(
          config: config(delivery_path: root),
          deliver: true,
          env: env,
          github: github,
          generator: ->(*) { flunk "provider must not be called" },
          telegram_factory: -> { telegram }
        )

        error = assert_raises(Prdigest::ConfigError) { instance.call }

        assert_equal message, error.message
        assert_empty github.calls
        assert_empty telegram.network_sends
        refute File.exist?(File.join(root, "prose", "#{DATE}.json"))
      end
    end
  end

  def test_prose_checkpoint_namespace_is_separate_from_deterministic_delivery
    Dir.mktmpdir do |root|
      deterministic = Prdigest::DeliveryCheckpointStore.new(root: root)
      deterministic.with_checkpoint(
        date: DATE,
        chat_id: 1,
        scope: ["owner/repo"],
        chunks: ["deterministic"]
      ) { }
      telegram = CheckpointingTelegram.new

      runner(
        config: config(delivery_path: root),
        deliver: true,
        env: credentials,
        github: FakeGitHub.new,
        generator: FakeGenerator.new,
        renderer: FakeRenderer.new(chunks: ["generated prose"]),
        telegram_factory: -> { telegram }
      ).call

      assert_equal ["generated prose"], telegram.network_sends
      assert_equal ["deterministic"], checkpoint_chunks(File.join(root, "#{DATE}.json"))
      assert_equal ["generated prose"], checkpoint_chunks(File.join(root, "prose", "#{DATE}.json"))
    end
  end

  private

  def runner(config: config(delivery_path: "/tmp/prdigest-prose-runner-test"),
             date: nil, deliver: false, env: credentials, github: FakeGitHub.new,
             generator: FakeGenerator.new, renderer: FakeRenderer.new,
             telegram_factory: -> { CheckpointingTelegram.new },
             checkpoint_store_factory: nil)
    Prdigest::ProseRunner.new(
      config: config,
      date: date,
      deliver: deliver,
      repositories: ["owner/repo"],
      env: env,
      clock: FakeClock.new,
      github: github,
      generator: generator,
      renderer: renderer,
      telegram_factory: telegram_factory,
      checkpoint_store_factory: checkpoint_store_factory
    )
  end

  def config(delivery_path:)
    Prdigest::Config.new({
      "timezone" => "UTC",
      "github" => {
        "repos" => ["owner/repo"],
        "token_env" => "GITHUB_TOKEN"
      },
      "telegram" => {
        "token_env" => "TELEGRAM_BOT_TOKEN",
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
    })
  end

  def credentials
    {
      "GITHUB_TOKEN" => "github",
      "PROVIDER_KEY" => "provider",
      "TELEGRAM_BOT_TOKEN" => "telegram"
    }
  end

  def checkpoint_chunks(path)
    JSON.parse(File.read(path)).fetch("chunks")
  end
end
