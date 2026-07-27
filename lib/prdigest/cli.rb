# frozen_string_literal: true

require "date"
require "json"
require "thor"

module Prdigest
  class CLI < Thor
    class ParseError < StandardError; end

    EXIT_CODES = {
      "config" => 2, "cli" => 2, "refusal" => 2,
      "github" => 3,
      "telegram" => 4, "telegram_refused" => 4, "telegram_permanent" => 4,
      "telegram_ambiguous" => 4, "delivery_checkpoint" => 4,
      "delivery_checkpoint_permanent" => 4,
      "state" => 5,
      "provider" => 7, "provider_ambiguous" => 7
    }.freeze

    desc "facts", "Print deterministic merged-PR facts as JSON"
    def facts; end

    desc "prose", "Generate an optional AI-written merged-PR digest"
    def prose; end

    desc "version", "Print version"
    def version; end

    class << self
      def invoke(argv = ARGV, out: $stdout, err: $stderr, env: ENV,
                 system_path: "/etc/prdigest/config.yml", facts_runner_factory: nil,
                 prose_runner_factory: nil)
        intent = command_intent(argv)
        facts_intent = intent == "facts"
        prose_intent = intent == "prose"
        parsed = parse(argv)
        validate_command_options!(parsed, intent: intent)
        return print_version(out) if parsed[:command] == "version"
        raise ParseError, "--help is not valid for facts" if facts_intent && parsed[:command] == "help"
        return print_help(out) if %w[help --help -h].include?(parsed[:command])

        raise ParseError, "unknown command" unless %w[facts prose].include?(parsed[:command])

        path = Config.resolve_path(explicit: parsed[:config], env: env, system_path: system_path)
        capability = config_capability(parsed)
        config = Config.load(path, capability: capability)

        validate_date!(parsed[:date]) if parsed[:date]
        repositories = if parsed[:repos].empty?
                         nil
                       else
                         Config.normalize_repos(parsed[:repos], label: "--repo")
                       end
        if parsed[:command] == "facts"
          raise ConfigError, "GitHub token is missing" if config.github_token(env).empty?

          factory = facts_runner_factory || ->(**options) { FactsRunner.new(**options) }
          document = factory.call(
            config: config,
            date: parsed[:date],
            repositories: repositories,
            env: env
          ).call
          out.puts JSON.generate(document)
          return 0
        end

        if parsed[:command] == "prose"
          if parsed[:deliver]
            raise ConfigError, "Telegram bot token is missing" if config.telegram_token(env).empty?
          else
            raise ConfigError, "GitHub token is missing" if config.github_token(env).empty?
            if config.prose_api_key(env).empty?
              raise ConfigError, "prose API key environment variable is unset"
            end
          end

          factory = prose_runner_factory || ->(**options) { ProseRunner.new(**options) }
          outcome = factory.call(
            config: config,
            date: parsed[:date],
            deliver: parsed[:deliver],
            repositories: repositories,
            env: env
          ).call
          present_prose(outcome, out: out)
          return 0
        end
      rescue ParseError => e
        return present_facts_failure(out, "cli", e.message) if facts_intent
        return present_prose_failure(err, "cli", e.message) if prose_intent

        present_cli_failure(err, "cli", e.message)
      rescue ConfigError => e
        return present_facts_failure(out, "config", e.message) if facts_intent
        return present_prose_failure(err, "config", safe_prose_message(e, config: config, env: env)) if prose_intent

        present_cli_failure(err, "config", e.message)
      rescue StandardError => e
        if facts_intent
          kind = e.is_a?(FetchError) ? e.kind : "internal"
          message = e.is_a?(FetchError) ? e.message : "unexpected facts failure (#{e.class})"
          return present_facts_failure(out, kind, message)
        end
        if prose_intent
          kind = prose_error_kind(e)
          message = safe_prose_message(e, config: config, env: env)
          return present_prose_failure(err, kind, message)
        end

        present_cli_failure(err, "internal", "unexpected CLI failure (#{e.class})")
      end

      alias start invoke

      def exit_on_failure?
        true
      end

      private

      def command_intent(argv)
        args = Array(argv).dup
        until args.empty?
          argument = args.shift
          case argument
          when "--config", "--date", "--repo"
            args.shift
          when /\A--/
            next
          else
            return argument
          end
        end
        nil
      end

      def parse(argv)
        parsed = {
          command: nil,
          config: nil,
          date: nil,
          dry_run: false,
          json: false,
          deliver: false,
          repos: []
        }
        args = Array(argv).dup
        until args.empty?
          argument = args.shift
          case argument
          when "--help", "-h"
            parsed[:command] = "help"
          when "--dry-run"
            parsed[:dry_run] = true
          when "--json"
            parsed[:json] = true
          when "--deliver"
            parsed[:deliver] = true
          when "--config", "--date", "--repo"
            value = args.shift
            raise ParseError, "missing value for #{argument}" if value.nil? || value.start_with?("--")
            if argument == "--repo"
              parsed[:repos] << value
            else
              parsed[argument.delete_prefix("--").tr("-", "_").to_sym] = value
            end
          when /\A--config=(.*)\z/
            raise ParseError, "missing value for --config" if Regexp.last_match(1).empty?
            parsed[:config] = Regexp.last_match(1)
          when /\A--date=(.*)\z/
            raise ParseError, "missing value for --date" if Regexp.last_match(1).empty?
            parsed[:date] = Regexp.last_match(1)
          when /\A--repo=(.*)\z/
            raise ParseError, "missing value for --repo" if Regexp.last_match(1).empty?
            parsed[:repos] << Regexp.last_match(1)
          when /\A-/
            raise ParseError, "unknown option"
          else
            raise ParseError, "unexpected argument" if parsed[:command]
            parsed[:command] = argument
          end
        end
        parsed
      end

      def validate_date!(value)
        unless value.match?(/\A\d{4}-\d{2}-\d{2}\z/) && Date.iso8601(value).iso8601 == value
          raise ConfigError, "date must use YYYY-MM-DD"
        end
      rescue Date::Error
        raise ConfigError, "date must use YYYY-MM-DD"
      end

      def validate_command_options!(parsed, intent:)
        command = intent || parsed.fetch(:command)
        if parsed[:deliver] && command != "prose"
          raise ParseError, "--deliver is only valid for prose"
        end

        if command == "facts"
          raise ParseError, "--dry-run is not valid for facts" if parsed[:dry_run]
          raise ParseError, "--json is not valid for facts; output is always JSON" if parsed[:json]
        elsif command == "prose"
          raise ParseError, "--dry-run is not valid for prose" if parsed[:dry_run]
          raise ParseError, "--json is not valid for prose" if parsed[:json]
        end
      end

      def config_capability(parsed)
        case parsed.fetch(:command)
        when "facts" then :facts
        when "prose" then parsed[:deliver] ? :prose_delivery : :prose
        end
      end

      def present_facts_failure(out, error_kind, message)
        out.puts JSON.generate(Facts.failure(error_kind: error_kind, message: message))
        EXIT_CODES.fetch(error_kind.to_s, 1)
      end

      def present_prose(outcome, out:)
        if outcome.delivered?
          delivery = outcome.delivery
          out.puts(
            "prdigest: prose delivered; date=#{outcome.date} " \
            "chunks=#{delivery.fetch(:total_chunks)}"
          )
        else
          out.write("#{outcome.prose.to_s.sub(/(?:\r?\n)*\z/, "")}\n")
        end
      end

      def present_prose_failure(err, error_kind, message)
        err.puts "prdigest: #{error_kind}: #{message}"
        EXIT_CODES.fetch(error_kind.to_s, 1)
      end

      def present_cli_failure(err, error_kind, message)
        err.puts "prdigest: #{error_kind}: #{message}"
        EXIT_CODES.fetch(error_kind.to_s, 1)
      end

      def prose_error_kind(error)
        case error
        when FetchError then error.kind
        when SendError then error.kind
        when StateError then "state"
        when GenerationError then error.kind
        when RenderError then error.kind
        else "internal"
        end
      end

      def safe_prose_message(error, config:, env:)
        message = error.is_a?(Error) ? error.message : "unexpected prose failure (#{error.class})"
        return message unless config

        secrets = [
          config.github_token(env),
          config.telegram_token(env),
          config.prose_api_key(env)
        ]
        secrets.reject(&:empty?).reduce(message.dup) do |safe, secret|
          safe.gsub(secret, "[REDACTED]")
        end
      end

      def print_version(out)
        out.puts "prdigest #{VERSION}"
        0
      end

      def print_help(out)
        out.puts "Usage: prdigest facts [--config PATH] [--date YYYY-MM-DD] [--repo owner/name]"
        out.puts "       prdigest prose [--config PATH] [--date YYYY-MM-DD] [--repo owner/name] [--deliver]"
        out.puts "       prdigest version"
        0
      end
    end
  end
end
