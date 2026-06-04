# frozen_string_literal: true

RSpec.describe Daytona::Util do
  describe ".demux" do
    stdout = "\x01\x01\x01"
    stderr = "\x02\x02\x02"

    it "returns empty parts for an empty line" do
      expect(described_class.demux("")).to eq(["", ""])
    end

    it "extracts a single stdout run" do
      expect(described_class.demux("#{stdout}hello world")).to eq(["hello world", ""])
    end

    it "extracts a single stderr run" do
      expect(described_class.demux("#{stderr}boom")).to eq(["", "boom"])
    end

    it "splits interleaved stdout and stderr runs in order" do
      line = "#{stdout}out1#{stderr}err1#{stdout}out2"
      expect(described_class.demux(line)).to eq(["out1out2", "err1"])
    end

    it "drops leading bytes that precede any stream prefix" do
      # No prefix seen yet -> state is nil -> bytes are discarded.
      expect(described_class.demux("noise#{stdout}kept")).to eq(["kept", ""])
    end

    it "preserves JSON payloads carried on the stdout stream" do
      line = %(#{stdout}{"type":"a"}\n#{stdout}{"type":"b"}\n)
      out, err = described_class.demux(line)
      expect(out).to eq(%({"type":"a"}\n{"type":"b"}\n))
      expect(err).to eq("")
    end

    it "treats the input as binary regardless of source encoding" do
      out, = described_class.demux("#{stdout}café".dup.force_encoding(Encoding::UTF_8))
      expect(out.b).to eq("café".b)
    end
  end
end
