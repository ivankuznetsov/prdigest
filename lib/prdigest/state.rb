# frozen_string_literal: true

require "date"
require "fileutils"
require "json"
require "securerandom"

module Prdigest
  class State
    VERSION = 1
    Record = Data.define(:last_digested_date, :last_skip)

    def initialize(path:, timezone:, rename: File.method(:rename))
      @path = File.expand_path(path)
      @timezone = timezone
      @rename = rename
    end

    def read(yesterday: nil)
      return Record.new(nil, nil) unless File.exist?(@path)

      payload = JSON.parse(File.binread(@path))
      validate_payload!(payload, yesterday: yesterday)
    rescue StateError
      raise
    rescue StandardError => e
      raise StateError, "cannot read state: #{e.class}"
    end

    def write(last_digested_date:, last_skip: nil)
      directory = File.dirname(@path)
      FileUtils.mkdir_p(directory, mode: 0o700)
      temp_path = File.join(directory, ".#{File.basename(@path)}.tmp-#{SecureRandom.hex(8)}")
      payload = JSON.generate(serialize(last_digested_date, last_skip)) << "\n"

      File.open(temp_path, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
        file.write(payload)
        file.flush
        file.fsync
      end
      @rename.call(temp_path, @path)
      File.chmod(0o600, @path)
      File.open(directory, File::RDONLY) { |dir| dir.fsync }
      Record.new(Date.iso8601(last_digested_date.to_s), normalize_skip(last_skip))
    rescue StandardError => e
      raise StateError, "cannot write state: #{e.class}"
    ensure
      File.unlink(temp_path) if defined?(temp_path) && temp_path && File.exist?(temp_path)
    end

    private

    def validate_payload!(payload, yesterday:)
      raise StateError, "state root must be an object" unless payload.is_a?(Hash)
      raise StateError, "unsupported state version" unless payload["version"] == VERSION
      raise StateError, "state timezone does not match config" unless payload["timezone"] == @timezone

      value = payload["last_digested_date"]
      last_date = value.nil? ? nil : Date.iso8601(value)
      raise StateError, "state date is in the future" if yesterday && last_date && last_date > Date.iso8601(yesterday.to_s)

      skip = parse_skip(payload["last_skip"])
      Record.new(last_date, skip)
    rescue Date::Error, TypeError
      raise StateError, "state contains an invalid date"
    end

    def parse_skip(value)
      return nil if value.nil?
      raise StateError, "state last_skip is invalid" unless value.is_a?(Hash)

      {
        start_date: Date.iso8601(value.fetch("start_date")),
        end_date: Date.iso8601(value.fetch("end_date")),
        notice_pending: value.fetch("notice_pending") == true
      }
    rescue KeyError
      raise StateError, "state last_skip is invalid"
    end

    def normalize_skip(skip)
      return nil unless skip
      {
        start_date: Date.iso8601(skip.fetch(:start_date).to_s),
        end_date: Date.iso8601(skip.fetch(:end_date).to_s),
        notice_pending: skip.fetch(:notice_pending) == true
      }
    end

    def serialize(last_date, last_skip)
      payload = {
        version: VERSION,
        timezone: @timezone,
        last_digested_date: Date.iso8601(last_date.to_s).iso8601
      }
      if (skip = normalize_skip(last_skip))
        payload[:last_skip] = {
          start_date: skip[:start_date].iso8601,
          end_date: skip[:end_date].iso8601,
          notice_pending: skip[:notice_pending]
        }
      end
      payload
    end
  end
end
