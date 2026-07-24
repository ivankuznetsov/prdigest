# frozen_string_literal: true

require "date"
require "fileutils"
require "json"
require "securerandom"

module Prdigest
  class State
    VERSION = 1
    Record = Data.define(:last_digested_date, :last_skip)

    def initialize(path:, timezone:, rename: File.method(:rename), directory_sync: nil)
      @path = File.expand_path(path)
      @timezone = timezone
      @rename = rename
      @directory_sync = directory_sync || method(:sync_directory)
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
        file.chmod(0o600)
        file.flush
        file.fsync
      end
      rollback_path = preserve_previous_checkpoint(directory)
      @rename.call(temp_path, @path)
      begin
        @directory_sync.call(directory)
      rescue StandardError
        restore_previous_checkpoint(rollback_path)
        raise
      end
      Record.new(Date.iso8601(last_digested_date.to_s), normalize_skip(last_skip))
    rescue StandardError => e
      raise StateError, "cannot write state: #{e.class}"
    ensure
      File.unlink(temp_path) if defined?(temp_path) && temp_path && File.exist?(temp_path)
      discard_rollback(rollback_path) if defined?(rollback_path) && rollback_path
    end

    private

    def sync_directory(directory)
      File.open(directory, File::RDONLY) { |dir| dir.fsync }
    end

    def preserve_previous_checkpoint(directory)
      rollback_path = File.join(directory, ".#{File.basename(@path)}.rollback-#{SecureRandom.hex(8)}")
      File.link(@path, rollback_path)
      rollback_path
    rescue Errno::ENOENT
      nil
    end

    def restore_previous_checkpoint(rollback_path)
      if rollback_path
        File.rename(rollback_path, @path)
      else
        File.unlink(@path)
      end
    rescue Errno::ENOENT
      raise if rollback_path
      nil
    end

    def discard_rollback(rollback_path)
      FileUtils.rm_f(rollback_path) if rollback_path
    end

    def validate_payload!(payload, yesterday:)
      raise StateError, "state root must be an object" unless payload.is_a?(Hash)
      raise StateError, "unsupported state version" unless payload["version"] == VERSION
      raise StateError, "state timezone does not match config" unless payload["timezone"] == @timezone
      raise StateError, "state last_digested_date is required" unless payload.key?("last_digested_date")

      value = payload["last_digested_date"]
      last_date = Date.iso8601(value)
      raise StateError, "state date is in the future" if yesterday && last_date && last_date > Date.iso8601(yesterday.to_s)

      skip = parse_skip(payload["last_skip"])
      if skip && (skip[:start_date] > skip[:end_date] || skip[:end_date] > last_date)
        raise StateError, "state last_skip range is invalid"
      end
      Record.new(last_date, skip)
    rescue Date::Error, TypeError
      raise StateError, "state contains an invalid date"
    end

    def parse_skip(value)
      return nil if value.nil?
      raise StateError, "state last_skip is invalid" unless value.is_a?(Hash)

      pending = value.fetch("notice_pending")
      raise StateError, "state last_skip is invalid" unless pending == true || pending == false
      {
        start_date: Date.iso8601(value.fetch("start_date")),
        end_date: Date.iso8601(value.fetch("end_date")),
        notice_pending: pending
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
