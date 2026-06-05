# frozen_string_literal: true

RSpec.describe Daytona::Util::Demuxer do
  let(:out_p) { "\x01\x01\x01" }
  let(:err_p) { "\x02\x02\x02" }

  it "splits stdout and stderr within a single frame" do
    expect(described_class.new.feed("#{out_p}hi#{err_p}boom")).to eq(["hi", "boom"])
  end

  it "keeps a run that continues across frames (the bug Util.demux drops)" do
    d = described_class.new
    expect(d.feed("#{out_p}hello ")).to eq(["hello ", ""])
    # Continuation frame has no prefix — it must stay attributed to stdout.
    expect(d.feed("world\n")).to eq(["world\n", ""])
  end

  it "reassembles a prefix split across the frame boundary" do
    d = described_class.new
    # First frame ends with two of stdout's three prefix bytes...
    expect(d.feed("#{out_p}ab\x01\x01")).to eq(["ab", ""])
    # ...the third arrives next frame; the prefix must not corrupt the stream.
    expect(d.feed("\x01cd")).to eq(["cd", ""])
  end

  it "routes a continuation to stderr after a stderr prefix" do
    d = described_class.new
    expect(d.feed("#{err_p}line1")).to eq(["", "line1"])
    expect(d.feed("line2")).to eq(["", "line2"])
  end

  it "losslessly reassembles a large run chunked into arbitrary frames" do
    payload = ("x" * 200_000).b
    wire = "#{out_p}#{payload}".b
    d = described_class.new
    got = +"".b
    # Slice the wire into 7000-byte frames, like the WebSocket layer would.
    wire.bytes.each_slice(7000) do |bytes|
      out, = d.feed(bytes.pack("C*"))
      got << out
    end
    expect(got.bytesize).to eq(payload.bytesize)
    expect(got).to eq(payload)
  end

  it "demuxes interleaved stdout/stderr runs across frames" do
    d = described_class.new
    a = d.feed("#{out_p}out1#{err_p}er")
    b = d.feed("r1#{out_p}out2")
    out = a[0] + b[0]
    err = a[1] + b[1]
    expect(out).to eq("out1out2")
    expect(err).to eq("err1")
  end
end
