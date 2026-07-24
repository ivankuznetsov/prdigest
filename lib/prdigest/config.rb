# frozen_string_literal: true

require "yaml"
require "pathname"
require "tzinfo"

module Prdigest
  class Config
    attr_reader :raw, :path

    REPOSITORY_SEGMENT = /\A[A-Za-z0-9_.-]+\z/

    def self.resolve_path(explicit: nil, env: ENV, system_path: "/etc/prdigest/config.yml")
      return File.expand_path(explicit) if explicit && !explicit.to_s.empty?

      from_env = env["PRDIGEST_CONFIG"].to_s
      return File.expand_path(from_env) unless from_env.empty?
      return system_path if File.file?(system_path)

      raise ConfigError, "config path is required (--config, PRDIGEST_CONFIG, or /etc/prdigest/config.yml)"
    end

    def self.load(path)
      path = File.expand_path(path)
      raise ConfigError, "config not found: #{path}" unless File.file?(path)

      raw = YAML.safe_load_file(path, aliases: true)
      raise ConfigError, "config root must be a mapping" unless raw.is_a?(Hash)

      new(raw, path: path).tap(&:validate!)
    rescue ConfigError
      raise
    rescue StandardError => e
      raise ConfigError, "cannot load config: #{e.class}"
    end

    def self.normalize_repos(values, label: "repository")
      normalized = Array(values).map { |value| value.to_s.strip }
      raise ConfigError, "#{label} must list at least one owner/name" if normalized.empty?

      invalid = normalized.find do |repository|
        parts = repository.split("/", -1)
        parts.length != 2 ||
          parts.any? { |part| part.empty? || %w[. ..].include?(part) || !part.match?(REPOSITORY_SEGMENT) }
      end
      raise ConfigError, "#{label} entry must be owner/name; got #{invalid.inspect}" if invalid

      normalized.each_with_object({}) do |repository, unique|
        unique[repository.downcase] ||= repository
      end.values.freeze
    end

    def initialize(raw, path: nil)
      @raw = raw
      @path = path
    end

    def timezone
      raw.fetch("timezone", "UTC").to_s
    end

    def repos
      self.class.normalize_repos(raw.dig("github", "repos"), label: "github.repos")
    end

    def github_token(env = ENV)
      env_name = raw.dig("github", "token_env") || "GITHUB_TOKEN"
      env[env_name.to_s].to_s
    end

    def telegram_token(env = ENV)
      env_name = raw.dig("telegram", "token_env") || "TELEGRAM_BOT_TOKEN"
      env[env_name.to_s].to_s
    end

    def chat_id
      Integer(raw.dig("telegram", "chat_id"))
    rescue TypeError, ArgumentError
      nil
    end

    def chat_id_allowlist
      Array(raw.dig("telegram", "chat_id_allowlist")).map { |id| Integer(id) }
    rescue TypeError, ArgumentError
      []
    end

    def line_stats?
      raw.dig("digest", "line_stats") != false
    end

    def send_empty?
      raw.dig("digest", "send_empty") != false
    end

    def empty_message
      raw.dig("digest", "empty_message") || "Merged PR digest — {date}\nTotal: 0 PRs"
    end

    def state_path
      raw.dig("state", "path") || File.expand_path("~/.local/share/prdigest/state.json")
    end

    def schedule_cron
      raw.dig("schedule", "cron") || "5 9 * * *"
    end

    def max_catchup_days
      Integer(raw.dig("schedule", "max_catchup_days") || 7)
    rescue TypeError, ArgumentError
      raise ConfigError, "schedule.max_catchup_days must be an integer from 1 to 30"
    end

    def validate!
      begin
        TZInfo::Timezone.get(timezone)
      rescue TZInfo::InvalidTimezoneIdentifier
        raise ConfigError, "timezone must be a resolvable IANA identifier"
      end
      unless (1..30).cover?(max_catchup_days)
        raise ConfigError, "schedule.max_catchup_days must be from 1 to 30"
      end
      repos
      raise ConfigError, "telegram.chat_id is required" if chat_id.nil?
      raise ConfigError, "telegram.chat_id_allowlist must not be empty" if chat_id_allowlist.empty?
      unless chat_id_allowlist.include?(chat_id)
        raise ConfigError, "telegram.chat_id must be present in chat_id_allowlist"
      end
      self
    end
  end
end
