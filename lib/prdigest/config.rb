# frozen_string_literal: true

require "yaml"
require "pathname"
require "tzinfo"
require "uri"

module Prdigest
  class Config
    attr_reader :raw, :path

    REPOSITORY_SEGMENT = /\A[A-Za-z0-9_.-]+\z/
    ENVIRONMENT_VARIABLE = /\A[A-Za-z_][A-Za-z0-9_]*\z/
    PROSE_BASE_URL_ERROR =
      "prose.base_url must be an absolute HTTP(S) URL without credentials, query, or fragment"

    def self.resolve_path(explicit: nil, env: ENV, system_path: "/etc/prdigest/config.yml")
      return File.expand_path(explicit) if explicit && !explicit.to_s.empty?

      from_env = env["PRDIGEST_CONFIG"].to_s
      return File.expand_path(from_env) unless from_env.empty?
      return system_path if File.file?(system_path)

      raise ConfigError, "config path is required (--config, PRDIGEST_CONFIG, or /etc/prdigest/config.yml)"
    end

    def self.load(path, capability: :run)
      path = File.expand_path(path)
      raise ConfigError, "config not found: #{path}" unless File.file?(path)

      raw = YAML.safe_load_file(path, aliases: true)
      raise ConfigError, "config root must be a mapping" unless raw.is_a?(Hash)

      new(raw, path: path).tap { |config| config.validate!(capability: capability) }
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

    def self.parse_prose_base_uri(value)
      uri = URI.parse(value.to_s.strip)
      valid = %w[http https].include?(uri.scheme) &&
        !uri.host.to_s.empty? &&
        uri.userinfo.nil? &&
        uri.query.nil? &&
        uri.fragment.nil?
      raise ConfigError, PROSE_BASE_URL_ERROR unless valid

      uri
    rescue URI::InvalidURIError
      raise ConfigError, PROSE_BASE_URL_ERROR
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

    def prose_provider
      prose_config["provider"].to_s
    end

    def prose_base_url
      prose_config["base_url"].to_s.strip
    end

    def prose_model
      prose_config["model"].to_s.strip
    end

    def prose_api_key_env
      prose_config["api_key_env"].to_s.strip
    end

    def prose_api_key(env = ENV)
      env[prose_api_key_env].to_s
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

    def delivery_state_path
      raw.dig("state", "delivery_path") || File.join(File.dirname(state_path), "deliveries")
    end

    def schedule_cron
      raw.dig("schedule", "cron") || "5 9 * * *"
    end

    def max_catchup_days
      Integer(raw.dig("schedule", "max_catchup_days") || 7)
    rescue TypeError, ArgumentError
      raise ConfigError, "schedule.max_catchup_days must be an integer from 1 to 30"
    end

    def validate!(capability: :run)
      capability = capability.to_sym
      unless %i[facts run prose prose_delivery].include?(capability)
        raise ArgumentError, "unknown configuration capability: #{capability}"
      end

      begin
        TZInfo::Timezone.get(timezone)
      rescue TZInfo::InvalidTimezoneIdentifier
        raise ConfigError, "timezone must be a resolvable IANA identifier"
      end
      unless (1..30).cover?(max_catchup_days)
        raise ConfigError, "schedule.max_catchup_days must be from 1 to 30"
      end
      repos
      return self if capability == :facts

      validate_prose! if %i[prose prose_delivery].include?(capability)
      return self if capability == :prose

      validate_telegram!
      self
    end

    private

    def prose_config
      section = raw["prose"]
      section.is_a?(Hash) ? section : {}
    end

    def validate_prose!
      unless raw["prose"].is_a?(Hash)
        raise ConfigError, "prose must be a mapping"
      end
      if prose_config.key?("api_key")
        raise ConfigError, "prose API key must be supplied through an environment variable"
      end
      unless prose_provider == "openai_compatible"
        raise ConfigError, "prose.provider must be openai_compatible"
      end
      self.class.parse_prose_base_uri(prose_base_url)
      raise ConfigError, "prose.model must not be blank" if prose_model.empty?
      unless prose_api_key_env.match?(ENVIRONMENT_VARIABLE)
        raise ConfigError, "prose.api_key_env must name an environment variable"
      end
    end

    def validate_telegram!
      raise ConfigError, "telegram.chat_id is required" if chat_id.nil?
      raise ConfigError, "telegram.chat_id_allowlist must not be empty" if chat_id_allowlist.empty?
      unless chat_id_allowlist.include?(chat_id)
        raise ConfigError, "telegram.chat_id must be present in chat_id_allowlist"
      end
    end
  end
end
