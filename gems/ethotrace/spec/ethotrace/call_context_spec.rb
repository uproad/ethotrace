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
