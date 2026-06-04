# frozen_string_literal: true

RSpec.describe Daytona::Services::FileSystem do
  let(:base_url) { "https://api.daytona.io" }
  let(:api_key) { "test-api-key" }
  let(:http_client) { Daytona::API::HttpClient.new(base_url: base_url, api_key: api_key) }
  # base_service builds the toolbox URL from the http_client base_url:
  #   {base}/toolbox/{sandbox_id}/toolbox
  let(:toolbox) { "#{base_url}/toolbox/sbx1/toolbox" }

  def build
    described_class.new(http_client: http_client, sandbox_id: "sbx1", get_toolbox_url: -> { "unused" })
  end

  def json(body)
    { status: 200, body: body, headers: { "Content-Type" => "application/json" } }
  end

  # The toolbox routes are /files/*, NOT /filesystem/* — Daytona renamed them
  # and the old paths 404 with "Cannot POST/GET".
  describe "toolbox routes" do
    it "#create_folder POSTs /files/folder" do
      url = "#{toolbox}/files/folder"
      stub_request(:post, url).to_return(json("{}"))
      build.create_folder("/home/user/dir", "0755")
      expect(WebMock).to have_requested(:post, url)
        .with(body: { path: "/home/user/dir", mode: "0755" }.to_json)
    end

    it "#move_files POSTs /files/move" do
      url = "#{toolbox}/files/move"
      stub_request(:post, url).to_return(json("{}"))
      build.move_files("/a", "/b")
      expect(WebMock).to have_requested(:post, url)
    end

    it "#set_file_permissions POSTs /files/permissions" do
      url = "#{toolbox}/files/permissions"
      stub_request(:post, url).to_return(json("{}"))
      build.set_file_permissions("/a", mode: "0644")
      expect(WebMock).to have_requested(:post, url)
    end

    it "#download_file GETs /files/download with the path query" do
      url = "#{toolbox}/files/download"
      stub_request(:get, url).with(query: { path: "/a.txt" }).to_return(status: 200, body: "hi")
      expect(build.download_file("/a.txt")).to eq("hi")
      expect(WebMock).to have_requested(:get, url).with(query: { path: "/a.txt" })
    end

    it "#delete_file DELETEs /files with the path query" do
      url = "#{toolbox}/files"
      stub_request(:delete, url).with(query: { path: "/a.txt" }).to_return(status: 204, body: "")
      build.delete_file("/a.txt")
      expect(WebMock).to have_requested(:delete, url).with(query: { path: "/a.txt" })
    end
  end

  # HttpClient#get sets req.params, which would wipe any inline ?path= query —
  # the path must reach the server as a real query parameter.
  describe "#get_file_info" do
    it "GETs /files/info and sends the path as a query parameter" do
      url = "#{toolbox}/files/info"
      stub_request(:get, url).with(query: { path: "/root/x.ts" })
        .to_return(json('{"name":"x.ts","size":12}'))

      info = build.get_file_info("/root/x.ts")

      expect(info["size"]).to eq(12)
      expect(WebMock).to have_requested(:get, url).with(query: { path: "/root/x.ts" })
    end
  end

  describe "#list_files" do
    let(:url) { "#{toolbox}/files" }

    it "GETs /files with the path query and returns a bare array response" do
      stub_request(:get, url).with(query: { path: "/root" })
        .to_return(json('[{"name":"a"},{"name":"b"}]'))

      entries = build.list_files("/root")

      expect(entries.map { |e| e["name"] }).to eq(%w[a b])
      expect(WebMock).to have_requested(:get, url).with(query: { path: "/root" })
    end

    it "unwraps a legacy { entries: [...] } response" do
      stub_request(:get, url).with(query: { path: "/root" })
        .to_return(json('{"entries":[{"name":"a"}]}'))

      expect(build.list_files("/root").map { |e| e["name"] }).to eq(%w[a])
    end
  end

  describe "#write_file" do
    # The original failure: write_file -> upload_file -> upload_bytes must POST
    # multipart to /files/upload with the destination as the path query.
    it "POSTs multipart to /files/upload with the destination path query" do
      url = "#{toolbox}/files/upload"
      stub_request(:post, url).with(query: { path: "/root/pi-extensions/web-tools.ts" })
        .to_return(json("{}"))

      build.write_file("/root/pi-extensions/web-tools.ts", "export const ok = true\n")

      expect(WebMock).to have_requested(:post, url)
        .with(query: { path: "/root/pi-extensions/web-tools.ts" }) do |req|
          req.headers["Content-Type"].to_s.start_with?("multipart/form-data")
        end
    end
  end
end
