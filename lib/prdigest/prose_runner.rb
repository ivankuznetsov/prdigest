# frozen_string_literal: true

require "date"

module Prdigest
  class ProseRunner
    Outcome = Struct.new(:date, :prose, :delivery, keyword_init: true) do
      def delivered?
        !delivery.nil?
      end
    end

    GeneratedPayload = Struct.new(:prose, :chunks, keyword_init: true)

    def initialize(config:, date: nil, deliver: false, repositories: nil, env: ENV,
                   clock: nil, github: nil, generator: nil, renderer: nil,
                   telegram_factory: nil, checkpoint_store_factory: nil)
      @config = config
      @date = date && Date.iso8601(date.to_s)
      @deliver = deliver == true
      @repositories = repositories || config.repos
      @env = env
      @clock = clock || Clock.new(timezone: config.timezone)
      @github = github
      @generator = generator
      @renderer = renderer || ProseRenderer.new
      @telegram_factory = telegram_factory || method(:build_telegram)
      @checkpoint_store_factory = checkpoint_store_factory || method(:build_checkpoint_store)
    end

    def call
      date = @date || @clock.yesterday
      return deliver(date) if @deliver

      generated = generate(date)
      Outcome.new(date: date, prose: generated.prose)
    end

    def inspect
      "#<#{self.class} date=#{@date || "yesterday"} deliver=#{@deliver} credentials=[REDACTED]>"
    end

    alias to_s inspect

    private

    def deliver(date)
      delivery = @telegram_factory.call.deliver(
        digest_date: date,
        checkpoint_store: @checkpoint_store_factory.call,
        scope: @repositories,
        chunk_factory: -> { generate(date).chunks }
      )
      Outcome.new(date: date, delivery: delivery)
    end

    def generate(date)
      github_token = @config.github_token(@env)
      raise ConfigError, "GitHub token is missing" if github_token.empty?

      provider_key = @config.prose_api_key(@env)
      raise ConfigError, "prose API key environment variable is unset" if provider_key.empty?

      facts = FactsRunner.new(
        config: @config,
        date: date,
        repositories: @repositories,
        env: @env,
        clock: @clock,
        github: @github || GitHub.new(token: github_token)
      ).call
      prose = (@generator || build_generator(provider_key)).generate(facts)
      rendered = @renderer.render(prose)
      GeneratedPayload.new(prose: prose, chunks: rendered.chunks)
    end

    def build_generator(api_key)
      OpenAICompatible.new(
        api_key: api_key,
        base_url: @config.prose_base_url,
        model: @config.prose_model
      )
    end

    def build_telegram
      token = @config.telegram_token(@env)
      raise ConfigError, "Telegram bot token is missing" if token.empty?

      Telegram.new(
        token: token,
        chat_id: @config.chat_id,
        allowlist: @config.chat_id_allowlist
      )
    end

    def build_checkpoint_store
      DeliveryCheckpointStore.new(
        root: File.join(@config.delivery_state_path, "prose")
      )
    end
  end
end
