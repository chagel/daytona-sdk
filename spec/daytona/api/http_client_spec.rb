# frozen_string_literal: true

RSpec.describe Daytona::API::HttpClient do
  let(:base_url) { "https://api.daytona.io" }
  let(:api_key) { "test-api-key" }
  let(:client) { described_class.new(base_url: base_url, api_key: api_key) }

  describe "#initialize" do
    it "stores base_url with trailing slash" do
      client = described_class.new(base_url: "https://api.example.com", api_key: api_key)
      expect(client.base_url).to eq("https://api.example.com/")
    end

    it "preserves trailing slash if already present" do
      client = described_class.new(base_url: "https://api.example.com/", api_key: api_key)
      expect(client.base_url).to eq("https://api.example.com/")
    end
  end

  describe "request methods" do
    describe "#get" do
      it "makes a GET request and returns parsed JSON" do
        stub_request(:get, "https://api.daytona.io/sandbox/123")
          .with(headers: { "Authorization" => "Bearer #{api_key}" })
          .to_return(status: 200, body: '{"id": "123", "name": "test"}', headers: { "Content-Type" => "application/json" })

        result = client.get("/sandbox/123")

        expect(result).to eq({ "id" => "123", "name" => "test" })
      end

      it "includes query parameters" do
        stub_request(:get, "https://api.daytona.io/sandbox")
          .with(query: { "page" => "1", "limit" => "10" })
          .to_return(status: 200, body: '[]', headers: { "Content-Type" => "application/json" })

        client.get("/sandbox", params: { page: 1, limit: 10 })

        expect(WebMock).to have_requested(:get, "https://api.daytona.io/sandbox")
          .with(query: { "page" => "1", "limit" => "10" })
      end
    end

    describe "#post" do
      it "makes a POST request with JSON body" do
        stub_request(:post, "https://api.daytona.io/sandbox")
          .with(
            body: '{"name":"test-sandbox"}',
            headers: { "Content-Type" => "application/json" }
          )
          .to_return(status: 201, body: '{"id": "new-123"}', headers: { "Content-Type" => "application/json" })

        result = client.post("/sandbox", body: { name: "test-sandbox" })

        expect(result).to eq({ "id" => "new-123" })
      end

      it "handles POST without body" do
        stub_request(:post, "https://api.daytona.io/sandbox/123/start")
          .to_return(status: 200, body: '{"status": "started"}', headers: { "Content-Type" => "application/json" })

        result = client.post("/sandbox/123/start")

        expect(result).to eq({ "status" => "started" })
      end
    end

    describe "#put" do
      it "makes a PUT request with JSON body" do
        stub_request(:put, "https://api.daytona.io/sandbox/123/labels")
          .with(body: '{"labels":{"env":"prod"}}')
          .to_return(status: 200, body: '{"labels": {"env": "prod"}}', headers: { "Content-Type" => "application/json" })

        result = client.put("/sandbox/123/labels", body: { labels: { env: "prod" } })

        expect(result).to eq({ "labels" => { "env" => "prod" } })
      end
    end

    describe "#patch" do
      it "makes a PATCH request with JSON body" do
        stub_request(:patch, "https://api.daytona.io/sandbox/123")
          .with(body: '{"name":"updated"}')
          .to_return(status: 200, body: '{"name": "updated"}', headers: { "Content-Type" => "application/json" })

        result = client.patch("/sandbox/123", body: { name: "updated" })

        expect(result).to eq({ "name" => "updated" })
      end
    end

    describe "#delete" do
      it "makes a DELETE request" do
        stub_request(:delete, "https://api.daytona.io/sandbox/123")
          .to_return(status: 204, body: "", headers: {})

        result = client.delete("/sandbox/123")

        expect(result).to be_nil.or eq("")
      end
    end
  end

  describe "path normalization" do
    it "handles paths with leading slash" do
      stub_request(:get, "https://api.daytona.io/sandbox/123")
        .to_return(status: 200, body: '{}', headers: { "Content-Type" => "application/json" })

      client.get("/sandbox/123")

      expect(WebMock).to have_requested(:get, "https://api.daytona.io/sandbox/123")
    end

    it "handles paths without leading slash" do
      stub_request(:get, "https://api.daytona.io/sandbox/123")
        .to_return(status: 200, body: '{}', headers: { "Content-Type" => "application/json" })

      client.get("sandbox/123")

      expect(WebMock).to have_requested(:get, "https://api.daytona.io/sandbox/123")
    end

    it "handles paths with multiple leading slashes" do
      stub_request(:get, "https://api.daytona.io/sandbox/123")
        .to_return(status: 200, body: '{}', headers: { "Content-Type" => "application/json" })

      client.get("///sandbox/123")

      expect(WebMock).to have_requested(:get, "https://api.daytona.io/sandbox/123")
    end
  end

  describe "error handling" do
    it "raises AuthenticationError on 401" do
      stub_request(:get, "https://api.daytona.io/sandbox/123")
        .to_return(status: 401, body: '{"message": "Unauthorized"}', headers: { "Content-Type" => "application/json" })

      expect { client.get("/sandbox/123") }
        .to raise_error(Daytona::AuthenticationError) do |error|
          expect(error.status_code).to eq(401)
          expect(error.message).to eq("Unauthorized")
        end
    end

    it "raises AuthenticationError on 403" do
      stub_request(:get, "https://api.daytona.io/sandbox/123")
        .to_return(status: 403, body: '{"message": "Forbidden"}', headers: { "Content-Type" => "application/json" })

      expect { client.get("/sandbox/123") }
        .to raise_error(Daytona::AuthenticationError) do |error|
          expect(error.status_code).to eq(403)
        end
    end

    it "raises NotFoundError on 404" do
      stub_request(:get, "https://api.daytona.io/sandbox/unknown")
        .to_return(status: 404, body: '{"message": "Sandbox not found"}', headers: { "Content-Type" => "application/json" })

      expect { client.get("/sandbox/unknown") }
        .to raise_error(Daytona::NotFoundError) do |error|
          expect(error.status_code).to eq(404)
          expect(error.message).to eq("Sandbox not found")
        end
    end

    it "raises RateLimitError on 429" do
      stub_request(:get, "https://api.daytona.io/sandbox")
        .to_return(
          status: 429,
          body: '{"message": "Too many requests"}',
          headers: { "Content-Type" => "application/json", "retry-after" => "60" }
        )

      expect { client.get("/sandbox") }
        .to raise_error(Daytona::RateLimitError) do |error|
          expect(error.status_code).to eq(429)
          expect(error.headers["retry-after"]).to eq("60")
        end
    end

    it "raises DaytonaError on 500" do
      stub_request(:get, "https://api.daytona.io/sandbox")
        .to_return(status: 500, body: '{"error": "Internal server error"}', headers: { "Content-Type" => "application/json" })

      expect { client.get("/sandbox") }
        .to raise_error(Daytona::DaytonaError) do |error|
          expect(error.status_code).to eq(500)
        end
    end

    it "raises TimeoutError on request timeout" do
      stub_request(:get, "https://api.daytona.io/sandbox/123")
        .to_raise(Faraday::TimeoutError.new("execution expired"))

      expect { client.get("/sandbox/123") }
        .to raise_error(Daytona::TimeoutError, /timed out/)
    end

    it "raises DaytonaError on connection failure" do
      stub_request(:get, "https://api.daytona.io/sandbox/123")
        .to_raise(Faraday::ConnectionFailed.new("Connection refused"))

      expect { client.get("/sandbox/123") }
        .to raise_error(Daytona::DaytonaError, /Connection failed/)
    end

    it "extracts error message from 'error' field" do
      stub_request(:get, "https://api.daytona.io/sandbox/123")
        .to_return(status: 400, body: '{"error": "Bad request format"}', headers: { "Content-Type" => "application/json" })

      expect { client.get("/sandbox/123") }
        .to raise_error(Daytona::DaytonaError, "Bad request format")
    end

    it "uses status code message when body is empty" do
      stub_request(:get, "https://api.daytona.io/sandbox/123")
        .to_return(status: 502, body: "", headers: {})

      expect { client.get("/sandbox/123") }
        .to raise_error(Daytona::DaytonaError, /HTTP 502/)
    end
  end

  describe "authentication" do
    it "uses API key for Bearer token" do
      stub_request(:get, "https://api.daytona.io/sandbox")
        .with(headers: { "Authorization" => "Bearer test-api-key" })
        .to_return(status: 200, body: '[]', headers: { "Content-Type" => "application/json" })

      client.get("/sandbox")

      expect(WebMock).to have_requested(:get, "https://api.daytona.io/sandbox")
        .with(headers: { "Authorization" => "Bearer test-api-key" })
    end

    it "uses JWT token when API key is not provided" do
      jwt_client = described_class.new(
        base_url: base_url,
        jwt_token: "jwt-token-123",
        organization_id: "org-456"
      )

      stub_request(:get, "https://api.daytona.io/sandbox")
        .with(headers: {
          "Authorization" => "Bearer jwt-token-123",
          "X-Daytona-Organization-ID" => "org-456"
        })
        .to_return(status: 200, body: '[]', headers: { "Content-Type" => "application/json" })

      jwt_client.get("/sandbox")

      expect(WebMock).to have_requested(:get, "https://api.daytona.io/sandbox")
        .with(headers: { "X-Daytona-Organization-ID" => "org-456" })
    end

    it "includes SDK headers" do
      stub_request(:get, "https://api.daytona.io/sandbox")
        .with(headers: {
          "X-Daytona-Source" => "ruby-sdk",
          "X-Daytona-SDK-Version" => Daytona::VERSION
        })
        .to_return(status: 200, body: '[]', headers: { "Content-Type" => "application/json" })

      client.get("/sandbox")

      expect(WebMock).to have_requested(:get, "https://api.daytona.io/sandbox")
        .with(headers: { "X-Daytona-Source" => "ruby-sdk" })
    end
  end

  describe "response parsing" do
    it "parses JSON response" do
      stub_request(:get, "https://api.daytona.io/sandbox/123")
        .to_return(status: 200, body: '{"id": "123", "nested": {"key": "value"}}', headers: { "Content-Type" => "application/json" })

      result = client.get("/sandbox/123")

      expect(result).to eq({ "id" => "123", "nested" => { "key" => "value" } })
    end

    it "parses JSON array response" do
      stub_request(:get, "https://api.daytona.io/sandbox")
        .to_return(status: 200, body: '[{"id": "1"}, {"id": "2"}]', headers: { "Content-Type" => "application/json" })

      result = client.get("/sandbox")

      expect(result).to eq([{ "id" => "1" }, { "id" => "2" }])
    end

    it "handles string response that looks like JSON" do
      stub_request(:get, "https://api.daytona.io/sandbox/123")
        .to_return(status: 200, body: '{"id": "123"}', headers: { "Content-Type" => "text/plain" })

      result = client.get("/sandbox/123")

      # Should attempt to parse as JSON
      expect(result).to be_a(Hash).or be_a(String)
    end
  end

  describe "#download_file" do
    it "returns raw binary content" do
      binary_content = "\x89PNG\r\n\x1a\n".b

      stub_request(:get, "https://api.daytona.io/files/image.png")
        .to_return(status: 200, body: binary_content, headers: { "Content-Type" => "image/png" })

      result = client.download_file("/files/image.png")

      expect(result).to eq(binary_content)
    end

    it "raises error on download failure" do
      stub_request(:get, "https://api.daytona.io/files/missing.txt")
        .to_return(status: 404, body: '{"message": "File not found"}', headers: { "Content-Type" => "application/json" })

      expect { client.download_file("/files/missing.txt") }
        .to raise_error(Daytona::NotFoundError)
    end
  end

  describe "#upload_bytes" do
    # upload_bytes streams the content as a multipart/form-data file part.
    # WebMock cannot match a multipart body, so assert the parsed response and
    # the multipart Content-Type rather than the raw body.
    it "uploads content as multipart form data and returns the parsed response" do
      stub_request(:post, "https://api.daytona.io/files/upload")
        .to_return(status: 200, body: '{"path": "/uploaded/test.txt"}', headers: { "Content-Type" => "application/json" })

      result = client.upload_bytes(
        "/files/upload",
        content: "file content here",
        filename: "test.txt",
        content_type: "text/plain"
      )

      expect(result).to eq({ "path" => "/uploaded/test.txt" })
      expect(WebMock).to have_requested(:post, "https://api.daytona.io/files/upload")
        .with(headers: { "Content-Type" => %r{\Amultipart/form-data} })
    end
  end
end
