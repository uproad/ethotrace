# frozen_string_literal: true

require "ethotrace/cli"
require "tmpdir"

RSpec.describe Ethotrace::CLI::MergeCommand do
  let(:out) { StringIO.new }
  let(:err) { StringIO.new }

  around do |example|
    Dir.mktmpdir { |dir| @dir = dir and example.run }
  end

  def run(*argv)
    described_class.new(out: out, err: err).run(argv)
  end

  def fixture(name, records)
    path = File.join(@dir, name)
    File.write(path, records.map { |r| JSON.generate(r) }.join("\n"))
    path
  end

  def session_record(id)
    { schema_version: 1, type: "session", session: id, adapters: [], options: {} }
  end

  def observation(owner:, name:, kind: "instance", return_classes: [], samples: 1, session: "s1")
    {
      schema_version: 1,
      type: "method_observation",
      method: { owner: owner, name: name, kind: kind },
      site: nil,
      params: [],
      return: { classes_seen: return_classes },
      errors: [],
      requirements: [],
      samples: samples,
      session: session
    }
  end

  def parse_lines(io)
    io.string.each_line.map { |line| JSON.parse(line, symbolize_names: true) }
  end

  it "returns 1 and reports when no files are given" do
    expect(run).to eq(1)
    expect(err.string).to match(/no input files/)
  end

  it "merges observations of the same method across files into one JSONL line on stdout" do
    a = fixture("a.jsonl", [session_record("a"),
                            observation(owner: "Order", name: "total", return_classes: ["Integer"], session: "a")])
    b = fixture("b.jsonl", [session_record("b"),
                            observation(owner: "Order", name: "total", return_classes: ["NilClass"],
                                        samples: 2, session: "b")])

    expect(run(a, b)).to eq(0)
    lines = parse_lines(out)
    expect(lines.size).to eq(1)
    expect(lines.first).to include(
      type: "method_observation",
      method: { owner: "Order", name: "total", kind: "instance" },
      return: { classes_seen: %w[Integer NilClass] },
      samples: 3,
      sessions: %w[a b]
    )
  end

  it "writes to the -o path (creating directories) and keeps stdout empty" do
    src = fixture("a.jsonl", [observation(owner: "O", name: "m", session: "a")])
    output = File.join(@dir, "nested", "observations.jsonl")

    expect(run(src, "-o", output)).to eq(0)
    expect(out.string).to be_empty
    expect(File).to exist(output)
    records = File.readlines(output).map { |line| JSON.parse(line, symbolize_names: true) }
    expect(records.first).to include(type: "method_observation", method: include(owner: "O", name: "m"))
  end

  it "reports a summary to stderr without polluting stdout" do
    src = fixture("a.jsonl", [observation(owner: "O", name: "m", session: "a")])
    run(src)
    expect(err.string).to match(/merged 1 observations from 1 session\(s\) across 1 file\(s\) -> stdout/)
  end

  it "expands glob patterns the shell left unexpanded" do
    fixture("w1.jsonl", [observation(owner: "O", name: "m", session: "a")])
    fixture("w2.jsonl", [observation(owner: "O", name: "m", session: "b")])

    expect(run(File.join(@dir, "*.jsonl"))).to eq(0)
    lines = parse_lines(out)
    expect(lines.size).to eq(1)
    expect(lines.first[:sessions]).to eq(%w[a b])
  end

  it "produces output that is itself re-mergeable" do
    src = fixture("a.jsonl", [observation(owner: "O", name: "m", samples: 2, session: "a")])
    merged = File.join(@dir, "merged.jsonl")
    run(src, "-o", merged)

    again = fixture("b.jsonl", [observation(owner: "O", name: "m", samples: 5, session: "c")])
    second = described_class.new(out: (out2 = StringIO.new), err: err)
    second.run([merged, again])
    line = JSON.parse(out2.string.lines.first, symbolize_names: true)
    expect(line[:samples]).to eq(7)
    expect(line[:sessions]).to eq(%w[a c])
  end
end
