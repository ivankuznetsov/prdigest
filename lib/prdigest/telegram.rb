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

    def deliver(chunks)
      refuse_unlisted_chat! unless @allowlist.include?(@chat_id)
      Array(chunks).each do |chunk|
        @sleeper.call(1) if @delivered_chunk
        deliver_chunk(chunk.to_s)
        @delivered_chunk = true
      end
      true
    end

    def inspect
      "#<#{self.class} chat_id=#{@chat_id} token=[REDACTED]>"
    end

    alias to_s inspect

    private

    def deliver_chunk(text)
      attempts = 0
      waited = 0
      loop do
        attempts += 1
        begin
          response = @transport.call(
            uri: request_uri,
            request: build_request(text),
            open_timeout: 10,
            read_timeout: 30,
            write_timeout: 30
          )
        rescue StandardError => e
          fail_send!("transport") unless transient_transport?(e) && attempts < MAX_ATTEMPTS
          waited = wait!(attempts, "transport", waited)
          next
        end
        disposition, delay, kind = classify_response(response)
        return true if disposition == :success
        fail_send!(kind) unless disposition == :retry && attempts < MAX_ATTEMPTS
        waited = wait!(delay || attempts, kind, waited)
      end
    end

    def build_request(text)
      request = Net::HTTP::Post.new(request_uri.request_uri)
      request["Content-Type"] = "application/json"
      request.body = JSON.generate(
        chat_id: @chat_id,
        text: text,
        parse_mode: "HTML",
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

    def transient_transport?(error)
      error.is_a?(Timeout::Error) || error.is_a?(IOError) ||
        error.is_a?(SocketError) || error.is_a?(SystemCallError)
    end

    def wait!(seconds, kind, waited)
      delay = Integer(seconds, exception: false)
      total = waited + delay.to_i
      fail_send!("retry_wait_exceeded") unless delay && total <= MAX_RETRY_WAIT
      @sleeper.call(delay)
      total
    rescue SendError
      raise
    rescue StandardError
      fail_send!(kind)
    end

    def refuse_unlisted_chat!
      raise SendError.new("Telegram delivery refused: chat is not allowlisted", kind: "telegram_refused")
    end

    def fail_send!(kind)
      raise SendError.new("Telegram send failed (#{kind})", kind: "telegram")
    end
  end
end
