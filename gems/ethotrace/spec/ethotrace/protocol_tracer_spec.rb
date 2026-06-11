# frozen_string_literal: true

RSpec.describe Ethotrace::ProtocolTracer do
  # 引数役のフィクスチャ。protocol 観測対象となる Ruby 定義メソッドを持つ。
  let(:arg_class) do
    Class.new do
      def label = "x"

      def combine(left, right) = left + right

      def each_pair(&block) = block&.call

      def with_rest(*values) = values.size
    end
  end

  after do
    described_class.disable
    Ethotrace::ArgumentTable.reset
  end

  def context(owner: "Order", name: :total, kind: :instance)
    Ethotrace::CallContext.new(owner: owner, name: name, kind: kind)
  end

  # 追跡登録した arg に対して block を実行し、その間だけ TracePoint を有効化する。
  def observing(arg, ctx, trace_c_call: false)
    Ethotrace::ArgumentTable.track(ctx, [arg])
    described_class.enable(trace_c_call: trace_c_call)
    yield
  ensure
    described_class.disable
  end

  describe "#enabled? / #enable / #disable" do
    it "reports enabled state and is idempotent on enable" do
      expect(described_class.enabled?).to be(false)
      described_class.enable
      described_class.enable
      expect(described_class.enabled?).to be(true)
      described_class.disable
      expect(described_class.enabled?).to be(false)
    end
  end

  describe "protocol observation via :call" do
    it "records a Ruby method called on a tracked argument" do
      arg = arg_class.new
      ctx = context
      observing(arg, ctx) { arg.label }
      expect(ctx.to_observation[:params].first[:protocol])
        .to include(a_hash_including(name: "label", arity: 0, block: false))
    end

    it "records the positional arity actually passed" do
      arg = arg_class.new
      ctx = context
      observing(arg, ctx) { arg.combine(1, 2) }
      expect(ctx.to_observation[:params].first[:protocol])
        .to include(a_hash_including(name: "combine", arity: 2))
    end

    it "detects a block passed to an explicit block parameter" do
      arg = arg_class.new
      ctx = context
      observing(arg, ctx) { arg.each_pair { :noop } }
      expect(ctx.to_observation[:params].first[:protocol])
        .to include(a_hash_including(name: "each_pair", block: true))
    end

    it "counts splat arguments by their actual length" do
      arg = arg_class.new
      ctx = context
      observing(arg, ctx) { arg.with_rest(:a, :b, :c) }
      expect(ctx.to_observation[:params].first[:protocol])
        .to include(a_hash_including(name: "with_rest", arity: 3))
    end

    it "does not record calls on objects that are not tracked" do
      arg = arg_class.new
      other = arg_class.new
      ctx = context
      observing(arg, ctx) { other.label }
      expect(ctx.to_observation[:params].first[:protocol]).to eq([])
    end

    it "attributes a call to every active context owning the argument" do
      arg = arg_class.new
      outer = context(owner: "A")
      inner = context(owner: "B")
      Ethotrace::ArgumentTable.track(outer, [arg])
      Ethotrace::ArgumentTable.track(inner, [arg])
      described_class.enable
      arg.label
      described_class.disable
      expect(outer.to_observation[:params].first[:protocol]).not_to be_empty
      expect(inner.to_observation[:params].first[:protocol]).not_to be_empty
    end

    it "does not observe C methods when :c_call is off" do
      arg = +"hello"
      ctx = context
      observing(arg, ctx) { arg.upcase }
      protocol = ctx.to_observation[:params].first&.fetch(:protocol) || []
      expect(protocol.map { |e| e[:name] }).not_to include("upcase")
    end
  end

  describe "protocol observation via :c_call (opt-in)" do
    it "records a C method called on a tracked argument" do
      arg = +"hello"
      ctx = context
      observing(arg, ctx, trace_c_call: true) { arg.upcase }
      names = ctx.to_observation[:params].first[:protocol].map { |e| e[:name] }
      expect(names).to include("upcase")
    end
  end

  describe "reentrancy" do
    it "ignores events fired while inside the tracer guard" do
      arg = arg_class.new
      ctx = context
      Ethotrace::ArgumentTable.track(ctx, [arg])
      described_class.enable
      Ethotrace::ReentryGuard.guard { arg.label }
      described_class.disable
      expect(ctx.to_observation[:params].first[:protocol]).to eq([])
    end
  end
end
