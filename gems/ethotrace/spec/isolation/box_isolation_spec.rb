# frozen_string_literal: true

# BoxIsolation(Isolation::Box)の越境動作の回帰 spec。box 内 probe が組み立てた観測が
# root の Collector へ届くこと(ブリッジ)と、box 内 Ethotrace が root と別実体になること
# (実体分離)を、実環境の Ruby::Box で固定する。
#
# Ruby::Box は experimental かつ RUBY_BOX=1 でのみ有効化されるため、通常スイートでは
# skip し、専用 CI ジョブ(RUBY_BOX=1 + Ruby >= 4.0)でのみ実行する。
#
# 重要な系譜依存(docs/box-semantics.md): BoxIsolation は **main box からの起動**を前提と
# する。既に Ethotrace をロード済みの非 main box(RUBY_BOX=1 下の RSpec ランナーは
# `#<Ruby::Box:_,root>`)から作った子 box は親定義を共有し、分離しない。さらに共有系譜では
# box Collector == root Collector となり、RootSink が同一 Collector へ再 publish して再帰する。
# そのため非 main box では計装メソッドの呼び出し(配信)を行わず、分離が成立しないことのみ確認する。
RSpec.describe Ethotrace::Isolation::Box, :box do
  before do
    skip "Ruby::Box が無効。RUBY_BOX=1 + Ruby >= 4.0 で実行すること" unless described_class.available?
    Ethotrace::Collector.reset!
    Ethotrace::Wrapper.reset!
  end

  after do
    Ethotrace::Collector.reset!
    Ethotrace::Wrapper.reset!
  end

  let(:registry) { double("registry", adapters: []) }
  let(:strategy) { described_class.new }

  it "builds an isolated child box whose Ethotrace is a separate instance only from the main box" do
    strategy.install_probe(registry)

    box_tracker_id = strategy.box.eval("Ethotrace::Tracker.object_id")
    if Ruby::Box.current.main?
      expect(box_tracker_id).not_to eq(Ethotrace::Tracker.object_id)
    else
      expect(box_tracker_id).to eq(Ethotrace::Tracker.object_id)
    end
  ensure
    strategy.uninstall_probe(registry)
  end

  it "drops the child box on uninstall" do
    strategy.install_probe(registry)
    expect(strategy.box).not_to be_nil

    strategy.uninstall_probe(registry)
    expect(strategy.box).to be_nil
  end

  # 配信(box 内 probe → root Collector)の検証は、再帰しない main box 系譜でのみ行う。
  context "when launched from the main box" do
    before { skip "main box からの起動が必要(非 main box では子 box が分離しない)" unless Ruby::Box.current.main? }

    it "delivers a box-internal observation to a root-side Collector subscriber" do
      strategy.install_probe(registry)
      box = strategy.box
      box.eval('class Greeter; def hi(name) = "hi " + name; end')
      box.eval("Ethotrace::Isolation::BoxBridge").wrap("Greeter", :hi)

      observed = []
      Ethotrace::Collector.subscribe(->(ctx) { observed << ctx.to_observation })

      result = box.eval("Greeter").new.hi("world")

      expect(result).to eq("hi world") # ラッパー透過: 戻り値は不変
      expect(observed.size).to eq(1)
      expect(observed.first[:method]).to include(owner: "Greeter", name: "hi", kind: "instance")
      expect(observed.first[:return][:classes_seen]).to include("String")
    ensure
      strategy.uninstall_probe(registry)
    end
  end
end
