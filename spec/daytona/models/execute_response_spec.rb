# frozen_string_literal: true

RSpec.describe Daytona::Models::SessionExecuteRequest do
  describe "#to_h" do
    it "serializes camelCase keys and omits nils" do
      req = described_class.new(command: "pi --mode rpc")
      expect(req.to_h).to eq(command: "pi --mode rpc")
    end

    it "includes runAsync and suppressInputEcho when set" do
      req = described_class.new(command: "pi", run_async: true, suppress_input_echo: true)
      expect(req.to_h).to eq(command: "pi", runAsync: true, suppressInputEcho: true)
    end

    it "carries cwd and pty alongside the other options" do
      req = described_class.new(command: "ls", cwd: "/work", pty: false, suppress_input_echo: false)
      expect(req.to_h).to eq(command: "ls", cwd: "/work", pty: false, suppressInputEcho: false)
    end
  end
end

RSpec.describe Daytona::Models::SessionExecuteResponse do
  describe ".from_hash" do
    it "reads the command id from camelCase or snake_case" do
      expect(described_class.from_hash("cmdId" => "c1").cmd_id).to eq("c1")
      expect(described_class.from_hash("cmd_id" => "c2").cmd_id).to eq("c2")
    end

    it "returns nil for a nil payload" do
      expect(described_class.from_hash(nil)).to be_nil
    end
  end
end
