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

    desc "version", "Print version"
    def version; end

    desc "serve", "Compatibility stub; use the systemd timer"
    def serve; end

    class << self
      def invoke(argv = ARGV, out: $stdout, err: $stderr, env: ENV,
                 system_path: "/etc/prdigest/config.yml", runner_factory: nil)
        json_intent = Array(argv).any? { |arg| arg == "--json" || arg.start_with?("--json=") }
        parsed = parse(argv)
        return print_version(out) if parsed[:command] == "version"
        return print_help(out) if %w[help --help -h].include?(parsed[:command])

        unless %w[run serve].include?(parsed[:command])
          raise ParseError, "unknown command"
        end

        path = Config.resolve_path(explicit: parsed[:config], env: env, system_path: system_path)
        config = Config.load(path)
        if parsed[:command] == "serve"
          err.puts "prdigest serve: deferred in v0.1.0 — use systemd timer + `prdigest run`"
          return 0
        end

        validate_date!(parsed[:date]) if parsed[:date]
        repositories = if parsed[:repos].empty?
                         nil
                       else
                         Config.normalize_repos(parsed[:repos], label: "--repo")
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
        result = Result.failure(mode: "scheduled", error_kind: "cli", message: e.message)
        present(result, json: json_intent, out: out, err: err)
        result.exit_code
      rescue ConfigError => e
        result = Result.failure(mode: parsed && parsed[:date] ? "explicit_date_replay" : "scheduled", error_kind: "config", message: e.message)
        present(result, json: parsed ? parsed[:json] : json_intent, out: out, err: err)
        result.exit_code
      rescue StandardError => e
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

      def parse(argv)
        parsed = { command: nil, config: nil, date: nil, dry_run: false, json: false, repos: [] }
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
        out.puts "       prdigest serve | version"
        0
      end
    end
  end
end
