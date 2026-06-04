# frozen_string_literal: true

RSpec.describe Daytona::Services::Process do
  let(:base_url) { "https://api.daytona.io" }
  let(:api_key) { "test-api-key" }
  let(:http_client) { Daytona::API::HttpClient.new(base_url: base_url, api_key: api_key) }
  let(:preview) { { "url" => "https://preview.example/", "token" => "tok" } }
  # base_service builds the toolbox URL from the http_client base_url:
  #   {base}/toolbox/{sandbox_id}/toolbox
  let(:toolbox) { "#{base_url}/toolbox/sbx1/toolbox" }

  def build(get_preview_link: ->(_port) { preview })
    described_class.new(
      http_client: http_client,
      sandbox_id: "sbx1",
      get_toolbox_url: -> { "unused" },
      get_preview_link: get_preview_link
    )
  end

  describe "#send_session_command_input" do
    it "POSTs the data to the command's input endpoint" do
      url = "#{toolbox}/process/session/s1/command/c1/input"
      stub_request(:post, url)
        .with(body: { data: "hello\n" }.to_json)
        .to_return(status: 200, body: "{}", headers: { "Content-Type" => "application/json" })

      build.send_session_command_input("s1", "c1", "hello\n")

      expect(WebMock).to have_requested(:post, url).with(body: { data: "hello\n" }.to_json)
    end
  end

  describe "#get_session_command_logs_async" do
    # Minimal stand-in for WebSocket::Client::Simple::Client: records handlers
    # and lets the test drive on(:message)/on(:close).
    class FakeWS
      attr_reader :url, :headers

      def initialize(url, headers)
        @url = url
        @headers = headers
        @handlers = {}
      end

      def on(event, &block)
        @handlers[event] = block
      end

      def ready?
        @handlers.key?(:message) && @handlers.key?(:close)
      end

      def emit(event, arg = nil)
        @handlers.fetch(event).call(arg)
      end

      def close; end
    end

    Message = Struct.new(:type, :data)

    it "raises when no preview link is configured" do
      process = build(get_preview_link: nil)
      expect do
        process.get_session_command_logs_async("s1", "c1", on_stdout: ->(_) {}, on_stderr: ->(_) {})
      end.to raise_error(Daytona::DaytonaError, /get_preview_link/)
    end

    it "connects a follow WebSocket with the preview token and demuxes messages" do
      fake = nil
      allow(WebSocket::Client::Simple).to receive(:connect) do |url, headers:|
        fake = FakeWS.new(url, headers)
      end

      outs = []
      errs = []
      thread = Thread.new do
        build.get_session_command_logs_async(
          "s1", "c1",
          on_stdout: ->(chunk) { outs << chunk },
          on_stderr: ->(chunk) { errs << chunk }
        )
      end

      sleep(0.01) until fake&.ready?
      fake.emit(:message, Message.new(:text, "\x01\x01\x01hi\x02\x02\x02boom"))
      fake.emit(:close)
      thread.join(2)

      expect(outs.join).to eq("hi")
      expect(errs.join).to eq("boom")
      expect(fake.url).to eq("wss://preview.example/process/session/s1/command/c1/logs?follow=true")
      expect(fake.headers["X-Daytona-Preview-Token"]).to eq("tok")
    end

    it "stops streaming when it receives a close-type message" do
      fake = nil
      allow(WebSocket::Client::Simple).to receive(:connect) do |url, headers:|
        fake = FakeWS.new(url, headers)
      end

      thread = Thread.new do
        build.get_session_command_logs_async("s1", "c1", on_stdout: ->(_) {}, on_stderr: ->(_) {})
      end

      sleep(0.01) until fake&.ready?
      fake.emit(:message, Message.new(:close, nil))

      expect(thread.join(2)).to eq(thread)
    end
  end
end
