# frozen_string_literal: true

require "json"
require "net/http"
require "openssl"
require "timeout"
require "uri"

module Prdigest
  class Telegram
    MAX_ATTEMPTS = 3
    MAX_RETRY_WAIT = 60
    API_ORIGIN = "https://api.telegram.org"

    class NetHTTPTransport
      def call(uri:, request:, open_timeout:, read_timeout:, write_timeout:)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
        http.verify_hostname = true if http.respond_to?(:verify_hostname=)
        http.open_timeout = open_timeout
        http.read_timeout = read_timeout
        http.write_timeout = write_timeout if http.respond_to?(:write_timeout=)
        http.request(request)
      end
    end

    def initialize(token:, chat_id:, allowlist:, transport: NetHTTPTransport.new, sleeper: ->(seconds) { sleep(seconds) })
      @token = token.to_s
      @chat_id = Integer(chat_id)
      @allowlist = Array(allowlist).map { |id| Integer(id) }.freeze
      @transport = transport
      @sleeper = sleeper
      @delivered_chunk = false
    end

    def deliver(chunks = nil, digest_date:, checkpoint_store:, scope:, chunk_factory: nil)
      refuse_unlisted_chat! unless @allowlist.include?(@chat_id)
      checkpoint_store.with_checkpoint(
        date: digest_date,
        chat_id: @chat_id,
        scope: scope,
        chunks: chunks,
        chunk_factory: chunk_factory
      ) do |delivery|
        @delivered_chunk ||= delivery.next_chunk.positive?
        (delivery.next_chunk...delivery.chunks.length).each do |index|
          @sleeper.call(1) if @delivered_chunk
          deliver_chunk(delivery, index)
          @delivered_chunk = true
        end
        delivery.delivery
      end
    end

    def inspect
      "#<#{self.class} chat_id=#{@chat_id} token=[REDACTED]>"
    end

    alias to_s inspect

    private

    def deliver_chunk(delivery, index)
      attempts = 0
      waited = 0
      loop do
        attempts += 1
        delivery.begin_attempt(index)
        begin
          response = @transport.call(
            uri: request_uri,
            request: build_request(delivery.chunks.fetch(index)),
            open_timeout: 10,
            read_timeout: 30,
            write_timeout: 30
          )
        rescue StandardError => e
          fail_ambiguous!(delivery, index, e)
        end

        disposition, delay, kind = classify_response(response)
        if disposition == :success
          delivery.accept(index)
          return true
        end

        permanent = disposition == :failure
        delivery.reject(
          index,
          kind: permanent ? "telegram_permanent" : "telegram",
          message: failure_message(kind),
          permanent: permanent
        )
        fail_send!(
          delivery,
          index,
          kind: permanent ? "telegram_permanent" : "telegram",
          reason: kind
        ) if permanent || attempts >= MAX_ATTEMPTS

        waited = wait!(delay || attempts, kind, waited, delivery, index)
      end
    end

    def build_request(text)
      request = Net::HTTP::Post.new(request_uri.request_uri)
      request["Content-Type"] = "application/json"
      request.body = JSON.generate(
        chat_id: @chat_id,
        text: text,
        link_preview_options: { is_disabled: true }
      )
      request
    end

    def request_uri
      URI("#{API_ORIGIN}/bot#{@token}/sendMessage")
    end

    def classify_response(response)
      code = Integer(response.code)
      payload = JSON.parse(response.body.to_s)
      return [:success, nil, nil] if (200..299).cover?(code) && payload["ok"] == true

      if code == 429
        delay = Integer(payload.dig("parameters", "retry_after"), exception: false)
        return [:retry, delay, "rate_limited"]
      end
      return [:retry, nil, "server"] if (500..599).cover?(code)

      [:failure, nil, "http_#{code}"]
    rescue JSON::ParserError, TypeError, ArgumentError
      code && (500..599).cover?(code) ? [:retry, nil, "server"] : [:failure, nil, "invalid_response"]
    end

    def wait!(seconds, kind, waited, delivery, index)
      delay = Integer(seconds, exception: false)
      total = waited + delay.to_i
      fail_send!(delivery, index, reason: "retry_wait_exceeded") unless delay && total <= MAX_RETRY_WAIT
      @sleeper.call(delay)
      total
    rescue SendError
      raise
    rescue StandardError
      fail_send!(delivery, index, reason: kind)
    end

    def refuse_unlisted_chat!
      raise SendError.new("Telegram delivery refused: chat is not allowlisted", kind: "telegram_refused")
    end

    def fail_ambiguous!(delivery, index, error)
      reason = case error
               when Timeout::Error then "timeout"
               when IOError then "io"
               when SocketError then "socket"
               when SystemCallError then "system"
               else "transport"
               end
      raise SendError.new(
        "Telegram send outcome is ambiguous (#{reason})",
        kind: "telegram_ambiguous",
        delivery: delivery.delivery(failed_chunk: index)
      )
    end

    def fail_send!(delivery, index, kind: "telegram", reason:)
      raise SendError.new(
        failure_message(reason),
        kind: kind,
        delivery: delivery.delivery(failed_chunk: index)
      )
    end

    def failure_message(reason)
      "Telegram send failed (#{reason})"
    end
  end
end
