# frozen_string_literal: true

require_relative "test_helper"

class TelegramTest < Minitest::Test
  Response = Struct.new(:code, :body, keyword_init: true)

  class FakeHTTP
    attr_accessor :use_ssl, :verify_mode, :verify_hostname, :open_timeout, :read_timeout, :write_timeout
    attr_reader :requests

    def initialize(response)
      @response = response
      @requests = []
    end

    def request(request)
      @requests << request
      @response
    end
  end

  class FakeTransport
    attr_reader :calls

    def initialize(responses)
      @responses = responses.dup
      @calls = []
    end

    def call(uri:, request:, open_timeout:, read_timeout:, write_timeout:)
      @calls << { uri: uri, request: request, timeouts: [open_timeout, read_timeout, write_timeout] }
      response = @responses.shift
      raise response if response.is_a?(Exception)
      response
    end
  end

  def test_sends_expected_json_to_fixed_tls_origin
    transport = FakeTransport.new([ok])
    sender(transport: transport).deliver(["<b>Hello</b>"])
    call = transport.calls.fetch(0)
    assert_equal "https", call[:uri].scheme
    assert_equal "api.telegram.org", call[:uri].host
    assert_equal "/botsynthetic-secret/sendMessage", call[:uri].path
    payload = JSON.parse(call[:request].body)
    assert_equal(-1001, payload["chat_id"])
    assert_equal "<b>Hello</b>", payload["text"]
    assert_equal "HTML", payload["parse_mode"]
    assert_equal true, payload["link_preview_options"]["is_disabled"]
    assert_equal [10, 30, 30], call[:timeouts]
  end

  def test_refuses_unlisted_chat_before_transport
    transport = FakeTransport.new([ok])
    error = assert_raises(Prdigest::SendError) do
      sender(transport: transport, chat_id: 2, allowlist: [1]).deliver(["hello"])
    end
    assert_equal "telegram_refused", error.kind
    assert_empty transport.calls
  end

  def test_honors_rate_limit_and_caps_attempts
    sleeps = []
    limited = Response.new(code: "429", body: fixture("rate_limited.json"))
    transport = FakeTransport.new([limited, ok])
    sender(transport: transport, sleeper: ->(seconds) { sleeps << seconds }).deliver(["hello"])
    assert_equal [2], sleeps
    assert_equal 2, transport.calls.length

    excessive = Response.new(code: "429", body: JSON.generate(ok: false, parameters: { retry_after: 61 }))
    error = assert_raises(Prdigest::SendError) do
      sender(transport: FakeTransport.new([excessive]), sleeper: ->(*) { flunk "must not sleep" }).deliver(["hello"])
    end
    assert_match(/retry_wait_exceeded/, error.message)

    repeated = FakeTransport.new([limited, limited, limited])
    assert_raises(Prdigest::SendError) { sender(transport: repeated, sleeper: ->(*) {}).deliver(["hello"]) }
    assert_equal 3, repeated.calls.length
  end

  def test_retry_waits_share_one_sixty_second_budget
    sleeps = []
    limited = Response.new(
      code: "429",
      body: JSON.generate(ok: false, parameters: { retry_after: 31 })
    )
    transport = FakeTransport.new([limited, limited, ok])

    error = assert_raises(Prdigest::SendError) do
      sender(transport: transport, sleeper: ->(seconds) { sleeps << seconds }).deliver(["hello"])
    end

    assert_match(/retry_wait_exceeded/, error.message)
    assert_equal [31], sleeps
    assert_equal 2, transport.calls.length
  end

  def test_retries_transport_and_server_errors_but_not_other_failures
    transport = FakeTransport.new([Timeout::Error.new("slow synthetic-secret"), Response.new(code: "500", body: "{}"), ok])
    sender(transport: transport, sleeper: ->(*) {}).deliver(["hello"])
    assert_equal 3, transport.calls.length

    [Response.new(code: "400", body: fixture("send_error.json")), Response.new(code: "200", body: fixture("send_error.json"))].each do |response|
      transport = FakeTransport.new([response, ok])
      assert_raises(Prdigest::SendError) { sender(transport: transport).deliver(["hello"]) }
      assert_equal 1, transport.calls.length
    end
  end

  def test_paces_chunks_and_stops_on_later_failure
    sleeps = []
    transport = FakeTransport.new([ok, Response.new(code: "400", body: "{}")])
    assert_raises(Prdigest::SendError) do
      sender(transport: transport, sleeper: ->(seconds) { sleeps << seconds }).deliver(["one", "two", "three"])
    end
    assert_equal [1], sleeps
    assert_equal %w[one two], transport.calls.map { |call| JSON.parse(call[:request].body).fetch("text") }
  end

  def test_paces_chunks_across_consecutive_deliver_calls
    sleeps = []
    transport = FakeTransport.new([ok, ok])
    client = sender(transport: transport, sleeper: ->(seconds) { sleeps << seconds })

    client.deliver(["day one"])
    client.deliver(["day two"])

    assert_equal [1], sleeps
  end

  def test_net_http_transport_enforces_tls_and_does_not_follow_redirects
    redirect = Response.new(code: "302", body: "synthetic redirect")
    http = FakeHTTP.new(redirect)
    uri = URI("https://api.telegram.org/botsynthetic/sendMessage")
    request = Net::HTTP::Post.new(uri.request_uri)

    response = Net::HTTP.stub(:new, ->(host, port) {
      assert_equal "api.telegram.org", host
      assert_equal 443, port
      http
    }) do
      Prdigest::Telegram::NetHTTPTransport.new.call(
        uri: uri, request: request, open_timeout: 10, read_timeout: 30, write_timeout: 30
      )
    end

    assert_same redirect, response
    assert_equal true, http.use_ssl
    assert_equal OpenSSL::SSL::VERIFY_PEER, http.verify_mode
    assert_equal true, http.verify_hostname
    assert_equal [10, 30, 30], [http.open_timeout, http.read_timeout, http.write_timeout]
    assert_equal [request], http.requests
  end

  def test_public_errors_and_inspection_redact_token
    token = "synthetic-secret"
    transport = FakeTransport.new(Array.new(3) { IOError.new("#{token} https://api.telegram.org/bot#{token}/sendMessage") })
    client = sender(transport: transport, token: token, sleeper: ->(*) {})
    error = assert_raises(Prdigest::SendError) { client.deliver(["hello"]) }
    [error.message, error.inspect, client.inspect].each { |surface| refute_includes surface, token }
  end

  private

  def sender(transport:, token: "synthetic-secret", chat_id: -1001, allowlist: [-1001], sleeper: ->(*) {})
    Prdigest::Telegram.new(token: token, chat_id: chat_id, allowlist: allowlist, transport: transport, sleeper: sleeper)
  end

  def ok
    Response.new(code: "200", body: fixture("send_ok.json"))
  end

  def fixture(name)
    File.read(File.join(__dir__, "fixtures", "telegram", name))
  end
end
