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

  # 規約クエリ(設計資料 §9 の MCP クエリ群)。すべて method_observation 形の
  # レコード配列、または文字列配列を返す純データである。
  describe "contract queries" do
    let(:env_read) { { kind: "env.read", write: false, direct: true, from: nil, detail: { key: "TAX" } } }
    let(:time_read) { { kind: "time.read", write: false, direct: true, from: nil, detail: {} } }
    let(:db_query) { { kind: "db.query", write: false, direct: false, from: "Item#price", detail: {} } }
    let(:key_error) { { class: "KeyError", origin: "inherited", from: "Hash#fetch" } }
    let(:arg_error) { { class: "ArgumentError", origin: "direct", from: nil } }

    subject(:catalog) do
      described_class.new(
        [
          observation(owner: "Pure", name: "add"), # requirements 空
          observation(owner: "Clock", name: "now", requirements: [time_read]),
          observation(owner: "Config", name: "rate", requirements: [env_read], errors: [key_error]),
          observation(owner: "Repo", name: "fetch", requirements: [db_query], errors: [arg_error])
        ]
      )
    end

    describe "#pure_methods" do
      it "returns only methods with no requirements (R=∅)" do
        expect(catalog.pure_methods.map { |r| r[:method][:name] }).to contain_exactly("add")
      end
    end

    describe "#flaky_suspects" do
      it "returns methods touching nondeterministic requirements by default" do
        expect(catalog.flaky_suspects.map { |r| r[:method][:owner] }).to contain_exactly("Clock")
      end

      it "honours a custom set of suspect kinds" do
        expect(catalog.flaky_suspects(kinds: ["db.query"]).map { |r| r[:method][:owner] })
          .to contain_exactly("Repo")
      end
    end

    describe "#requiring" do
      it "returns methods touching a given effect vocabulary" do
        expect(catalog.requiring(kind: "db.query").map { |r| r[:method][:owner] })
          .to contain_exactly("Repo")
      end

      it "returns [] when no method touches the effect" do
        expect(catalog.requiring(kind: "http.request")).to eq([])
      end
    end

    describe "#raisers" do
      it "returns every method whose Error channel is non-empty" do
        expect(catalog.raisers.map { |r| r[:method][:owner] }).to contain_exactly("Config", "Repo")
      end

      it "filters by a specific exception class when given" do
        expect(catalog.raisers(exception: "KeyError").map { |r| r[:method][:owner] })
          .to contain_exactly("Config")
      end
    end

    describe "#exceptions_of" do
      it "lists the exception classes a method can escape" do
        expect(catalog.exceptions_of(owner: "Config", name: "rate")).to contain_exactly("KeyError")
      end

      it "returns nil for an unobserved method" do
        expect(catalog.exceptions_of(owner: "Config", name: "missing")).to be_nil
      end
    end

    describe "#param_protocol" do
      let(:items_param) do
        {
          position: 0,
          name: "items",
          protocol: [{ name: "each", arity: 0, block: true }, { name: "size", arity: 0, block: false }],
          classes_seen: ["Array"]
        }
      end

      subject(:catalog) do
        described_class.new([observation(owner: "Order", name: "total", params: [items_param])])
      end

      it "returns the observed protocol for a given argument position" do
        expect(catalog.param_protocol(owner: "Order", name: "total", position: 0))
          .to eq(items_param[:protocol])
      end

      it "returns nil for an unobserved argument position" do
        expect(catalog.param_protocol(owner: "Order", name: "total", position: 9)).to be_nil
      end

      it "returns nil for an unobserved method" do
        expect(catalog.param_protocol(owner: "Order", name: "missing", position: 0)).to be_nil
      end
    end
  end
end
