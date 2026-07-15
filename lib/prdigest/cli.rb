# frozen_string_literal: true

require "json"
require "thor"

module Prdigest
  class CLI < Thor
    class_option :config,
                 type: :string,
                 default: ENV.fetch("PRDIGEST_CONFIG", "configs/config.example.yml"),
                 desc: "Path to config.yml"

    desc "run", "Build and send (or dry-run) a merged-PR digest for one local day"
    method_option :date, type: :string, desc: "Local day YYYY-MM-DD (default: yesterday in config timezone)"
    method_option :dry_run, type: :boolean, default: false, desc: "Print message, do not send"
    method_option :json, type: :boolean, default: false, desc: "Emit JSON on stdout"
    def run_cmd
      cfg = Config.load(options[:config])
      result = Runner.new(config: cfg, date: options[:date], dry_run: options[:dry_run]).call
      if options[:json]
        puts JSON.generate(result)
      else
        puts result[:message]
        warn "prdigest: scaffold only (#{result[:status]}); dry_run=#{result[:dry_run]}"
      end
    end
    map "run" => :run_cmd

    desc "version", "Print version"
    def version
      puts "prdigest #{VERSION}"
    end

    desc "serve", "Long-running scheduler (not implemented in scaffold)"
    def serve
      Config.load(options[:config])
      warn "prdigest serve: not implemented yet — use systemd timer + `prdigest run` for v1"
      exit 0
    end

    def self.exit_on_failure?
      true
    end
  end
end
