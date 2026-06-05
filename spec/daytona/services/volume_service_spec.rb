# frozen_string_literal: true

RSpec.describe Daytona::Services::VolumeService do
  let(:base_url) { "https://api.daytona.io" }
  let(:http_client) { Daytona::API::HttpClient.new(base_url: base_url, api_key: "k") }
  let(:service) { described_class.new(http_client) }

  def json(body)
    { status: 200, body: body, headers: { "Content-Type" => "application/json" } }
  end

  describe "#list" do
    # The /volumes endpoint returns a bare JSON array; indexing a String key
    # into an Array raises, so #list must branch on the type.
    it "parses a bare array response" do
      stub_request(:get, "#{base_url}/volumes")
        .to_return(json('[{"id":"v1","name":"a"},{"id":"v2","name":"b"}]'))

      volumes = service.list

      expect(volumes.map(&:name)).to eq(%w[a b])
    end

    it "unwraps a legacy { items: [...] } response" do
      stub_request(:get, "#{base_url}/volumes")
        .to_return(json('{"items":[{"id":"v1","name":"a"}]}'))

      expect(service.list.map(&:name)).to eq(%w[a])
    end
  end

  describe "#get_or_create" do
    it "returns the existing volume when one matches by name" do
      stub_request(:get, "#{base_url}/volumes")
        .to_return(json('[{"id":"v1","name":"skills"}]'))

      expect(service.get_or_create("skills").id).to eq("v1")
    end

    it "creates a volume when none matches" do
      stub_request(:get, "#{base_url}/volumes").to_return(json("[]"))
      stub_request(:post, "#{base_url}/volumes")
        .with(body: { name: "skills" }.to_json)
        .to_return(json('{"id":"v9","name":"skills"}'))

      expect(service.get_or_create("skills").id).to eq("v9")
    end
  end
end
