# frozen_string_literal: true

RSpec.describe Ethotrace::CallContext do
  def build(**overrides)
    described_class.new(
      owner: "Order",
      name: "total_price",
      kind: :instance,
      **overrides
    )
  end

  describe "the method descriptor" do
    it "exposes owner, name, and kind normalized to strings/symbols" do
      owner = Class.new { def self.to_s = "Order" }
      ctx = described_class.new(owner: owner, name: :call, kind: "singleton")
      expect(ctx.owner).to eq("Order")
      expect(ctx.name).to eq("call")
      expect(ctx.kind).to eq(:singleton)
    end

    it "defaults site to nil when the definition location is unknown" do
      expect(build.site).to be_nil
    end

    it "keeps a provided site hash" do
      site = { path: "app/models/order.rb", line: 12 }
      expect(build(site: site).site).to eq(site)
    end
  end

  describe "#record_return" do
    it "returns the value unchanged so the wrapper can pass it through" do
      ctx = build
      value = Object.new
      expect(ctx.record_return(value)).to be(value)
    end

    it "records the observed return class in classes_seen" do
      ctx = build
      ctx.record_return(42)
      expect(ctx.to_observation[:return][:classes_seen]).to eq(["Integer"])
    end

    it "records NilClass for a nil return value" do
      ctx = build
      ctx.record_return(nil)
      expect(ctx.to_observation[:return][:classes_seen]).to eq(["NilClass"])
    end

    it "keeps classes_seen as a deduplicated union" do
      ctx = build
      ctx.record_return(1)
      ctx.record_return(2)
      ctx.record_return("s")
      expect(ctx.to_observation[:return][:classes_seen]).to eq(%w[Integer String])
    end

    it "skips anonymous classes whose name is nil" do
      ctx = build
      ctx.record_return(Class.new.new)
      expect(ctx.to_observation[:return][:classes_seen]).to eq([])
    end

    it "is not fooled by an object overriding #class" do
      liar = Object.new
      def liar.class = String
      ctx = build
      ctx.record_return(liar)
      expect(ctx.to_observation[:return][:classes_seen]).to eq(["Object"])
    end
  end

  describe "#record_escaped_exception" do
    it "records the exception class as direct by default" do
      ctx = build
      ctx.record_escaped_exception(ArgumentError.new("bad"))
      expect(ctx.to_observation[:errors]).to eq(
        [{ class: "ArgumentError", origin: "direct", from: nil }]
      )
    end

    it "records inherited attribution with the propagating method" do
      ctx = build
      ctx.record_escaped_exception(KeyError.new, origin: "inherited", from: "Hash#fetch")
      expect(ctx.to_observation[:errors]).to eq(
        [{ class: "KeyError", origin: "inherited", from: "Hash#fetch" }]
      )
    end

    it "deduplicates identical escaped-exception entries" do
      ctx = build
      ctx.record_escaped_exception(KeyError.new, origin: "inherited", from: "Hash#fetch")
      ctx.record_escaped_exception(KeyError.new, origin: "inherited", from: "Hash#fetch")
      expect(ctx.to_observation[:errors].size).to eq(1)
    end

    it "keeps distinct entries for different origins of the same class" do
      ctx = build
      ctx.record_escaped_exception(KeyError.new)
      ctx.record_escaped_exception(KeyError.new, origin: "inherited", from: "Hash#fetch")
      expect(ctx.to_observation[:errors].size).to eq(2)
    end
  end

  describe "#add_requirement" do
    it "records an effect with all schema fields" do
      ctx = build
      ctx.add_requirement("env.read", write: false, direct: true, detail: { key: "TAX_RATE" })
      expect(ctx.to_observation[:requirements]).to eq(
        [{ kind: "env.read", write: false, direct: true, from: nil, detail: { key: "TAX_RATE" } }]
      )
    end

    it "records inherited attribution with the propagating method" do
      ctx = build
      ctx.add_requirement("db.query", write: false, direct: false, from: "Item#price", detail: {})
      entry = ctx.to_observation[:requirements].first
      expect(entry).to include(direct: false, from: "Item#price")
    end

    it "stringifies the kind and defaults from/detail" do
      ctx = build
      ctx.add_requirement(:"time.read", write: false, direct: true)
      expect(ctx.to_observation[:requirements].first).to eq(
        kind: "time.read", write: false, direct: true, from: nil, detail: {}
      )
    end

    it "deduplicates an identical effect fired more than once in one call" do
      ctx = build
      2.times { ctx.add_requirement("env.read", write: false, direct: true, detail: { key: "X" }) }
      expect(ctx.to_observation[:requirements].size).to eq(1)
    end
  end

  describe "#record_argument" do
    it "records the observed class of an argument in classes_seen" do
      ctx = build
      ctx.record_argument(0, [1, 2], name: :items)
      slot = ctx.to_observation[:params].first
      expect(slot).to include(position: 0, name: "items", classes_seen: ["Array"])
    end

    it "keeps the parameter name once provided even on later nil-name calls" do
      ctx = build
      ctx.record_argument(0, [], name: :items)
      ctx.record_protocol_call(0, :size, arity: 0, block: false)
      expect(ctx.to_observation[:params].first[:name]).to eq("items")
    end

    it "unions classes_seen for the same position without duplicates" do
      ctx = build
      ctx.record_argument(0, 1, name: :value)
      ctx.record_argument(0, "x", name: :value)
      ctx.record_argument(0, 2, name: :value)
      expect(ctx.to_observation[:params].first[:classes_seen]).to eq(%w[Integer String])
    end

    it "skips an argument whose class name is nil" do
      ctx = build
      ctx.record_argument(0, Class.new.new, name: :anon)
      expect(ctx.to_observation[:params].first[:classes_seen]).to eq([])
    end

    it "is not fooled by an argument overriding #class" do
      liar = Object.new
      def liar.class = String
      ctx = build
      ctx.record_argument(0, liar, name: :obj)
      expect(ctx.to_observation[:params].first[:classes_seen]).to eq(["Object"])
    end
  end

  describe "#record_protocol_call" do
    it "records a protocol entry with the (name, arity, block) grain" do
      ctx = build
      ctx.record_argument(0, [], name: :items)
      ctx.record_protocol_call(0, :each, arity: 0, block: true)
      expect(ctx.to_observation[:params].first[:protocol]).to eq(
        [{ name: "each", arity: 0, block: true }]
      )
    end

    it "deduplicates identical protocol entries" do
      ctx = build
      ctx.record_protocol_call(0, :size, arity: 0, block: false)
      ctx.record_protocol_call(0, :size, arity: 0, block: false)
      expect(ctx.to_observation[:params].first[:protocol].size).to eq(1)
    end

    it "keeps distinct entries differing only by arity or block" do
      ctx = build
      ctx.record_protocol_call(0, :fetch, arity: 1, block: false)
      ctx.record_protocol_call(0, :fetch, arity: 1, block: true)
      ctx.record_protocol_call(0, :fetch, arity: 2, block: false)
      expect(ctx.to_observation[:params].first[:protocol].size).to eq(3)
    end

    it "creates a slot with a nil name when no argument was registered first" do
      ctx = build
      ctx.record_protocol_call(2, :call, arity: 0, block: false)
      slot = ctx.to_observation[:params].first
      expect(slot).to include(position: 2, name: nil, classes_seen: [])
    end
  end

  describe "#to_observation params" do
    it "orders params by position ascending" do
      ctx = build
      ctx.record_argument(2, :c, name: :third)
      ctx.record_argument(0, :a, name: :first)
      ctx.record_argument(1, :b, name: :second)
      expect(ctx.to_observation[:params].map { |p| p[:position] }).to eq([0, 1, 2])
    end

    it "returns copies so callers cannot mutate internal protocol state" do
      ctx = build
      ctx.record_protocol_call(0, :each, arity: 0, block: true)
      ctx.to_observation[:params].first[:protocol] << { name: "tampered" }
      expect(ctx.to_observation[:params].first[:protocol].size).to eq(1)
    end
  end

  describe "#to_observation" do
    it "produces a schema-shaped method_observation record" do
      ctx = build(site: { path: "app/models/order.rb", line: 12 })
      ctx.record_return(100)
      ctx.record_escaped_exception(KeyError.new, origin: "inherited", from: "Hash#fetch")

      expect(ctx.to_observation).to eq(
        schema_version: Ethotrace::SCHEMA_VERSION,
        type: "method_observation",
        method: { owner: "Order", name: "total_price", kind: "instance" },
        site: { path: "app/models/order.rb", line: 12 },
        params: [],
        return: { classes_seen: ["Integer"] },
        errors: [{ class: "KeyError", origin: "inherited", from: "Hash#fetch" }],
        requirements: [],
        samples: 1
      )
    end

    it "counts a single call as one sample" do
      expect(build.to_observation[:samples]).to eq(1)
    end

    it "does not include session or captured_at (added by the writer)" do
      expect(build.to_observation).not_to include(:session, :captured_at)
    end

    it "returns copies so callers cannot mutate internal state" do
      ctx = build
      ctx.record_return(1)
      ctx.to_observation[:return][:classes_seen] << "Tampered"
      expect(ctx.to_observation[:return][:classes_seen]).to eq(["Integer"])
    end
  end
end
