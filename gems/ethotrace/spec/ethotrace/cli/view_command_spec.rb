# frozen_string_literal: true

require "ethotrace/cli"
require "tmpdir"

RSpec.describe Ethotrace::CLI::ViewCommand do
  let(:out) { StringIO.new }
  let(:err) { StringIO.new }

  around do |example|
    Dir.mktmpdir { |dir| @dir = dir and example.run }
  end

  # 既定で色なし(--no-color)で実行し、出力を素のまま検査する。
  def run(*argv)
    described_class.new(out: out, err: err).run(["--no-color", *argv])
  end

  def fixture(records)
    path = File.join(@dir, "obs.jsonl")
    File.write(path, records.map { |r| JSON.generate(r) }.join("\n"))
    path
  end

  def observation(owner:, name:, kind: "instance", return_classes: [], errors: [],
                  requirements: [], samples: 1)
    {
      schema_version: 1, type: "method_observation",
      method: { owner: owner, name: name, kind: kind },
      site: nil, params: [], return: { classes_seen: return_classes },
      errors: errors, requirements: requirements, samples: samples, session: "s1"
    }
  end

  it "returns 1 and reports when no files are given" do
    expect(run).to eq(1)
    expect(err.string).to match(/no input files/)
  end

  it "prints a summary listing each method by default" do
    path = fixture([
                     observation(owner: "Order", name: "total", return_classes: ["Integer"]),
                     observation(owner: "Order", name: "create", kind: "singleton")
                   ])
    expect(run(path)).to eq(0)
    expect(out.string).to include("[1] Order.create")
    expect(out.string).to include("[2] Order#total")
    expect(out.string).to include("return: Integer")
  end

  it "shows full detail for a valid --index" do
    path = fixture([observation(owner: "Order", name: "total", return_classes: ["Integer"])])
    expect(run(path, "-i", "1")).to eq(0)
    expect(out.string).to include("Order#total")
    # 空でも全セクションの枠を出す。
    expect(out.string).to include("return (Success):", "args (protocol):",
                                  "errors (Error):", "requirements:")
    expect(out.string).to include("(none observed)")
  end

  it "accepts the long forms --index and --method as aliases of -i / -m" do
    path = fixture([observation(owner: "Order", name: "total", return_classes: ["Integer"])])
    expect(run(path, "--index", "1")).to eq(0)
    expect(out.string).to include("Order#total")
  end

  it "renders requirements in the detail view" do
    requirement = { kind: "env.read", write: false, direct: true, from: nil, detail: { key: "TAX_RATE" } }
    path = fixture([observation(owner: "Order", name: "total", requirements: [requirement])])
    expect(run(path, "-i", "1")).to eq(0)
    expect(out.string).to include("requirements:")
    expect(out.string).to include("env.read")
    expect(out.string).to include("TAX_RATE")
  end

  it "returns 1 for an out-of-range --index" do
    path = fixture([observation(owner: "O", name: "m")])
    expect(run(path, "-i", "9")).to eq(1)
    expect(err.string).to match(/index out of range/)
  end

  it "shows detail for an exact --method id" do
    path = fixture([
                     observation(owner: "Order", name: "total"),
                     observation(owner: "Order", name: "create", kind: "singleton")
                   ])
    expect(run(path, "-m", "Order.create")).to eq(0)
    expect(out.string).to include("Order.create  (singleton)")
    expect(out.string).not_to include("Order#total  (instance)")
  end

  it "falls back to substring matching for --method" do
    path = fixture([observation(owner: "Order", name: "total_price")])
    expect(run(path, "-m", "total")).to eq(0)
    expect(out.string).to include("Order#total_price")
  end

  it "returns 1 when --method matches nothing" do
    path = fixture([observation(owner: "O", name: "m")])
    expect(run(path, "-m", "Nope")).to eq(1)
    expect(err.string).to match(/no method matching/)
  end

  it "notices when the input has no observations" do
    path = File.join(@dir, "only_session.jsonl")
    File.write(path, JSON.generate(schema_version: 1, type: "session", session: "s1"))
    expect(run(path)).to eq(0)
    expect(out.string).to match(/no observations/)
  end

  it "omits ANSI escapes when color is disabled" do
    path = fixture([observation(owner: "O", name: "m", errors: [{ class: "E", origin: "direct", from: nil }])])
    run(path)
    expect(out.string).not_to include("\e[")
  end
end
