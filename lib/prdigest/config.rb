# frozen_string_literal: true

require "yaml"
require "pathname"

module Prdigest
  class Config
    attr_reader :raw, :path

    def self.load(path)
      path = File.expand_path(path)
      raise ConfigError, "config not found: #{path}" unless File.file?(path)

      raw = YAML.safe_load_file(path, aliases: true)
      raise ConfigError, "config root must be a mapping" unless raw.is_a?(Hash)

      new(raw, path: path).tap(&:validate!)
    end

    def initialize(raw, path: nil)
      @raw = raw
      @path = path
    end

    def timezone
      raw.fetch("timezone", "UTC").to_s
    end

    def repos
      Array(raw.dig("github", "repos")).map(&:to_s).map(&:strip).reject(&:empty?)
    end

    def github_token
      env_name = raw.dig("github", "token_env") || "GITHUB_TOKEN"
      ENV[env_name.to_s].to_s
    end

    def telegram_token
      env_name = raw.dig("telegram", "token_env") || "TELEGRAM_BOT_TOKEN"
      ENV[env_name.to_s].to_s
    end

    def chat_id
      raw.dig("telegram", "chat_id")
    end

    def chat_id_allowlist
      Array(raw.dig("telegram", "chat_id_allowlist")).map { |id| Integer(id) }
    end

    def line_stats?
      raw.dig("digest", "line_stats") != false
    end

    def send_empty?
      raw.dig("digest", "send_empty") != false
    end

    def state_path
      raw.dig("state", "path") || File.expand_path("~/.local/share/prdigest/state.json")
    end

    def schedule_cron
      raw.dig("schedule", "cron") || "5 9 * * *"
    end

    def max_catchup_days
      Integer(raw.dig("schedule", "max_catchup_days") || 7)
    end

    def validate!
      raise ConfigError, "github.repos must list at least one owner/name" if repos.empty?
      repos.each do |repo|
        next if repo.match?(%r{\A[^/\s]+/[^/\s]+\z})

        raise ConfigError, "github.repos entry must be owner/name; got #{repo.inspect}"
      end
      raise ConfigError, "telegram.chat_id is required" if chat_id.nil?
      raise ConfigError, "telegram.chat_id_allowlist must not be empty" if chat_id_allowlist.empty?
      unless chat_id_allowlist.include?(Integer(chat_id))
        raise ConfigError, "telegram.chat_id must be present in chat_id_allowlist"
      end
      self
    end
  end
end
