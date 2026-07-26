# frozen_string_literal: true

require "date"
require "json"
require "thor"

module Prdigest
  class CLI < Thor
    class ParseError < StandardError; end

    desc "run", "Build and send (or dry-run) a merged-PR digest for one local day"
    def run_cmd; end
    map "run" => :run_cmd

    desc "facts", "Print deterministic merged-PR facts as JSON"
    def facts; end

    desc "prose", "Generate an optional AI-written merged-PR digest"
    def prose; end

    desc "version", "Print version"
    def version; end

    desc "serve", "Compatibility stub; use the systemd timer"
    def serve; end

    class << self
      def invoke(argv = ARGV, out: $stdout, err: $stderr, env: ENV,
                 system_path: "/etc/prdigest/config.yml", runner_factory: nil,
                 facts_runner_factory: nil, prose_runner_factory: nil)
        json_intent = Array(argv).any? { |arg| arg == "--json" || arg.start_with?("--json=") }
        intent = command_intent(argv)
        facts_intent = intent == "facts"
        prose_intent = intent == "prose"
        parsed = parse(argv)
        validate_command_options!(parsed, intent: intent)
        return print_version(out) if parsed[:command] == "version"
        raise ParseError, "--help is not valid for facts" if facts_intent && parsed[:command] == "help"
        return print_help(out) if %w[help --help -h].include?(parsed[:command])

        unless %w[facts prose run serve].include?(parsed[:command])
          raise ParseError, "unknown command"
        end

        path = Config.resolve_path(explicit: parsed[:config], env: env, system_path: system_path)
        capability = config_capability(parsed)
        config = Config.load(path, capability: capability)
        if parsed[:command] == "serve"
          err.puts "prdigest serve: deferred in v0.1.x — use systemd timer + `prdigest run`"
          return 0
        end

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

        raise ConfigError, "GitHub token is missing" if config.github_token(env).empty?
        if !parsed[:dry_run] && config.telegram_token(env).empty?
          raise ConfigError, "Telegram bot token is missing"
        end

        factory = runner_factory || ->(**options) { Runner.new(**options) }
        result = factory.call(
          config: config,
          date: parsed[:date],
          dry_run: parsed[:dry_run],
          repositories: repositories,
          env: env
        ).call
        present(result, json: parsed[:json], out: out, err: err)
        result.exit_code
      rescue ParseError => e
        return present_facts_failure(out, "cli", e.message) if facts_intent
        return present_prose_failure(err, "cli", e.message) if prose_intent

        result = Result.failure(mode: "scheduled", error_kind: "cli", message: e.message)
        present(result, json: json_intent, out: out, err: err)
        result.exit_code
      rescue ConfigError => e
        return present_facts_failure(out, "config", e.message) if facts_intent
        return present_prose_failure(err, "config", safe_prose_message(e, config: config, env: env)) if prose_intent

        result = Result.failure(mode: parsed && parsed[:date] ? "explicit_date_replay" : "scheduled", error_kind: "config", message: e.message)
        present(result, json: parsed ? parsed[:json] : json_intent, out: out, err: err)
        result.exit_code
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

        result = Result.failure(
          mode: parsed && parsed[:date] ? "explicit_date_replay" : "scheduled",
          error_kind: "internal",
          message: "unexpected CLI failure (#{e.class})"
        )
        present(result, json: parsed ? parsed[:json] : json_intent, out: out, err: err)
        result.exit_code
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
        else :run
        end
      end

      def present_facts_failure(out, error_kind, message)
        out.puts JSON.generate(Facts.failure(error_kind: error_kind, message: message))
        Result::EXIT_CODES.fetch(error_kind.to_s, 1)
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
        Result::EXIT_CODES.fetch(error_kind.to_s, 1)
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

      def present(result, json:, out:, err:)
        if json
          out.puts JSON.generate(result.to_h)
        elsif result.exit_code.zero?
          if result.status == "dry_run"
            out.puts result.chunks.join("\n\n")
          else
            out.puts "prdigest: success; settled=#{result.settled_days.length} skipped=#{result.skipped_days.length}"
          end
        else
          if result.status == "partial_failure"
            err.puts "prdigest: progress; settled=#{human_dates(result.settled_days)} " \
                     "skipped=#{human_dates(result.skipped_days)} remaining=#{human_dates(result.remaining_days)}"
          end
          err.puts "prdigest: #{result.error[:kind]}: #{result.error[:message]}"
        end
      end

      def human_dates(dates)
        values = Array(dates)
        values.empty? ? "none" : values.join(",")
      end

      def print_version(out)
        out.puts "prdigest #{VERSION}"
        0
      end

      def print_help(out)
        out.puts "Usage: prdigest run [--config PATH] [--date YYYY-MM-DD] [--repo owner/name] [--dry-run] [--json]"
        out.puts "       prdigest facts [--config PATH] [--date YYYY-MM-DD] [--repo owner/name]"
        out.puts "       prdigest prose [--config PATH] [--date YYYY-MM-DD] [--repo owner/name] [--deliver]"
        out.puts "       prdigest serve | version"
        0
      end
    end
  end
end
