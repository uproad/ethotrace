# frozen_string_literal: true

require "ethotrace/mcp"
require "json"
require "tmpdir"
require "stringio"

RSpec.describe Ethotrace::MCP::Catalog do
  # method_observation レコード(symbol キー)を最小限の指定で組み立てるヘルパ。
  def observation(owner:, name:, kind: "instance", requirements: [], errors: [], params: [], returns: [], samples: 1)
    {
      schema_version: 1,
      type: "method_observation",
      method: { owner: owner, name: name, kind: kind },
      site: { path: "lib/#{owner.downcase}.rb", line: 1 },
      params: params,
      return: { classes_seen: returns },
      errors: errors,
      requirements: requirements,
      samples: samples,
      session: "rspec-w1-pid1"
    }
  end

  describe ".load" do
    it "reads JSONL, merges by (owner, name, kind), and indexes" do
      records = [
        observation(owner: "Order", name: "total", returns: ["Integer"]),
        observation(owner: "Order", name: "total", returns: ["NilClass"]) # 同一メソッドの別観測
      ]
      Dir.mktmpdir do |dir|
        path = File.join(dir, "observations.jsonl")
        File.write(path, records.map { |r| JSON.generate(r) }.join("\n"))

        catalog = described_class.load(path, warn_io: StringIO.new)

        expect(catalog.methods.size).to eq(1) # マージで 1 レコードへ統合
        record = catalog.lookup(owner: "Order", name: "total")
        expect(record[:return][:classes_seen]).to contain_exactly("Integer", "NilClass")
        expect(record[:samples]).to eq(2)
      end
    end
  end

  describe "#lookup" do
    subject(:catalog) do
      described_class.new(
        [
          observation(owner: "Order", name: "total"),
          observation(owner: "Order", name: "total", kind: "singleton")
        ]
      )
    end

    it "returns the record for an instance method by default" do
      expect(catalog.lookup(owner: "Order", name: "total")[:method])
        .to include(owner: "Order", name: "total", kind: "instance")
    end

    it "distinguishes singleton from instance by kind" do
      expect(catalog.lookup(owner: "Order", name: "total", kind: "singleton")[:method][:kind])
        .to eq("singleton")
    end

    it "returns nil for an unobserved method (observed contract に無いもの)" do
      expect(catalog.lookup(owner: "Order", name: "missing")).to be_nil
    end
  end

  describe "#methods" do
    it "exposes every merged record" do
      catalog = described_class.new(
        [
          observation(owner: "A", name: "x"),
          observation(owner: "B", name: "y")
        ]
      )
      expect(catalog.methods.map { |r| r[:method][:owner] }).to contain_exactly("A", "B")
    end
  end
end
