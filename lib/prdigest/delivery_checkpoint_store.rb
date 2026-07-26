# frozen_string_literal: true

require "date"
require "digest"
require "fileutils"
require "json"
require "time"

module Prdigest
  class DeliveryCheckpointStore
    SCHEMA = "prdigest-delivery-checkpoint"
    SCHEMA_VERSION = 1

    class Session
      def initialize(path:, data:)
        @path = path
        @data = data
      end

      def chunks
        @data.fetch("chunks")
      end

      def next_chunk
        @data.fetch("next_chunk")
      end

      def completed?
        @data.fetch("status") == "completed"
      end

      def begin_attempt(index)
        require_next_chunk!(index)
        @data["in_flight"] = { "chunk" => index, "started_at" => timestamp }
        persist!
      end

      def accept(index)
        require_in_flight!(index)
        @data["next_chunk"] = index + 1
        @data["in_flight"] = nil
        @data["status"] = next_chunk == chunks.length ? "completed" : "pending"
        @data["permanent_error"] = nil
        persist!
      end

      def reject(index, kind:, message:, permanent:)
        require_in_flight!(index)
        @data["in_flight"] = nil
        if permanent
          @data["status"] = "blocked"
          @data["permanent_error"] = {
            "kind" => kind.to_s,
            "message" => message.to_s,
            "failed_chunk" => index
          }
        else
          @data["permanent_error"] = nil
        end
        persist!
      end

      def delivery(failed_chunk: nil)
        result = {
          accepted_chunks: next_chunk,
          total_chunks: chunks.length,
          status: @data.fetch("status")
        }
        result[:failed_chunk] = failed_chunk unless failed_chunk.nil?
        result
      end

      private

      def require_next_chunk!(index)
        return if index == next_chunk && @data["in_flight"].nil? && !completed?

        raise StateError, "delivery checkpoint transition is invalid"
      end

      def require_in_flight!(index)
        return if @data.dig("in_flight", "chunk") == index

        raise StateError, "delivery checkpoint transition is invalid"
      end

      def persist!
        @data["updated_at"] = timestamp
        DeliveryCheckpointStore.atomic_write(@path, JSON.pretty_generate(@data))
      rescue StateError
        raise
      rescue StandardError => e
        raise StateError, "cannot persist delivery checkpoint (#{e.class})"
      end

      def timestamp
        Time.now.utc.iso8601(6)
      end
    end

    def initialize(root:)
      @root = File.expand_path(root)
    end

    def with_checkpoint(date:, chat_id:, scope:, chunks: nil, chunk_factory: nil)
      normalized_date = Date.iso8601(date.to_s)
      ensure_root!
      path = File.join(@root, "#{normalized_date}.json")
      lock_path = File.join(@root, "#{normalized_date}.lock")

      File.open(lock_path, File::RDWR | File::CREAT, 0o600) do |lock|
        File.chmod(0o600, lock_path)
        unless lock.flock(File::LOCK_EX | File::LOCK_NB)
          raise SendError.new(
            "delivery checkpoint is already active",
            kind: "delivery_checkpoint",
            delivery: { accepted_chunks: 0, total_chunks: Array(chunks).length, status: "pending" }
          )
        end

        data = load_or_create(
          path,
          date: normalized_date,
          chat_id: Integer(chat_id),
          scope: Array(scope).map(&:to_s),
          chunks: chunks,
          chunk_factory: chunk_factory
        )
        fail_if_unavailable!(data)
        yield Session.new(path: path, data: data)
      ensure
        lock.flock(File::LOCK_UN)
      end
    rescue Error
      raise
    rescue StandardError => e
      raise StateError, "cannot access delivery checkpoint (#{e.class})"
    end

    def self.atomic_write(path, content)
      directory = File.dirname(path)
      temporary = "#{path}.tmp-#{Process.pid}-#{Thread.current.object_id}"
      File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
        file.write(content)
        file.flush
        file.fsync
      end
      File.rename(temporary, path)
      File.chmod(0o600, path)
      File.open(directory, File::RDONLY, &:fsync)
    ensure
      File.unlink(temporary) if temporary && File.exist?(temporary)
    end

    private

    def ensure_root!
      FileUtils.mkdir_p(@root, mode: 0o700)
      File.chmod(0o700, @root)
    end

    def load_or_create(path, date:, chat_id:, scope:, chunks:, chunk_factory:)
      if File.file?(path)
        data = JSON.parse(File.read(path))
        validate!(data, date: date, chat_id: chat_id, scope: scope)
        data
      else
        chunks = build_chunks(chunks, chunk_factory)
        data = {
          "schema" => SCHEMA,
          "schema_version" => SCHEMA_VERSION,
          "date" => date.to_s,
          "chat_id" => chat_id,
          "scope" => scope,
          "chunks" => chunks,
          "chunks_sha256" => chunk_digest(chunks),
          "next_chunk" => 0,
          "status" => chunks.empty? ? "completed" : "pending",
          "in_flight" => nil,
          "permanent_error" => nil,
          "created_at" => Time.now.utc.iso8601(6),
          "updated_at" => Time.now.utc.iso8601(6)
        }
        self.class.atomic_write(path, JSON.pretty_generate(data))
        data
      end
    rescue SendError
      raise
    rescue JSON::ParserError, KeyError, TypeError, ArgumentError => e
      raise SendError.new(
        "delivery checkpoint is invalid (#{e.class})",
        kind: "delivery_checkpoint_permanent"
      )
    end

    def build_chunks(chunks, chunk_factory)
      if chunk_factory.nil? == chunks.nil?
        raise StateError, "delivery checkpoint requires exactly one payload source"
      end

      source = chunk_factory ? chunk_factory.call : chunks
      Array(source).map(&:to_s)
    end

    def validate!(data, date:, chat_id:, scope:)
      expected = {
        "schema" => SCHEMA,
        "schema_version" => SCHEMA_VERSION,
        "date" => date.to_s,
        "chat_id" => chat_id,
        "scope" => scope
      }
      unless expected.all? { |key, value| data.fetch(key) == value }
        raise SendError.new(
          "delivery checkpoint does not match this digest",
          kind: "delivery_checkpoint_permanent"
        )
      end

      chunks = data.fetch("chunks")
      next_chunk = data.fetch("next_chunk")
      status = data.fetch("status")
      valid = chunks.is_a?(Array) && chunks.all? { |chunk| chunk.is_a?(String) } &&
              data.fetch("chunks_sha256") == chunk_digest(chunks) &&
              next_chunk.is_a?(Integer) && next_chunk.between?(0, chunks.length) &&
              valid_transition_state?(data, status: status, next_chunk: next_chunk, total_chunks: chunks.length)
      raise KeyError, "invalid delivery checkpoint fields" unless valid
    end

    def valid_transition_state?(data, status:, next_chunk:, total_chunks:)
      in_flight = data.fetch("in_flight")
      permanent_error = data.fetch("permanent_error")
      case status
      when "pending"
        next_chunk < total_chunks &&
          valid_in_flight?(in_flight, next_chunk) &&
          permanent_error.nil?
      when "completed"
        next_chunk == total_chunks && in_flight.nil? && permanent_error.nil?
      when "blocked"
        next_chunk < total_chunks && in_flight.nil? &&
          permanent_error.is_a?(Hash) &&
          permanent_error["kind"].is_a?(String) &&
          permanent_error["message"].is_a?(String) &&
          permanent_error["failed_chunk"] == next_chunk
      else
        false
      end
    end

    def valid_in_flight?(in_flight, next_chunk)
      in_flight.nil? ||
        (in_flight.is_a?(Hash) &&
         in_flight["chunk"] == next_chunk &&
         in_flight["started_at"].is_a?(String))
    end

    def fail_if_unavailable!(data)
      session = Session.new(path: "", data: data)
      if data["in_flight"]
        failed_chunk = data.dig("in_flight", "chunk")
        raise SendError.new(
          "Telegram delivery outcome is ambiguous; operator reconciliation is required",
          kind: "telegram_ambiguous",
          delivery: session.delivery(failed_chunk: failed_chunk)
        )
      end

      return unless data["status"] == "blocked"

      failure = data.fetch("permanent_error")
      raise SendError.new(
        failure.fetch("message"),
        kind: failure.fetch("kind"),
        delivery: session.delivery(failed_chunk: failure.fetch("failed_chunk"))
      )
    end

    def chunk_digest(chunks)
      ::Digest::SHA256.hexdigest(JSON.generate(chunks))
    end
  end
end
