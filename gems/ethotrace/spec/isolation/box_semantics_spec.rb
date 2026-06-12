# frozen_string_literal: true

# Ruby::Box セマンティクスの検証実験 E1〜E6(設計資料 v2 §4.8)を、回帰検出可能な
# 不変条件として固定する spec。自己適用(self-hosting)の隔離戦略 BoxIsolation は
# これらの前提の上に成り立つため、Ruby のマイナー更新で前提が崩れたら検出したい。
#
# Ruby::Box は experimental かつ RUBY_BOX=1 でのみ有効化されるため、通常スイートでは
# skip し、専用の CI ジョブ(RUBY_BOX=1 + Ruby >= 4.0)でのみ実行する。
# 結論の散文は docs/box-semantics.md を参照。手動再現は script/box_experiments.rb。
RSpec.describe "Ruby::Box semantics (design §4.8 E1-E6)", :box do
  before do
    skip "Ruby::Box が無効。RUBY_BOX=1 + Ruby >= 4.0 で実行すること" unless defined?(Ruby::Box) && Ruby::Box.enabled?
  end

  # core の lib(box から require するため)。spec/isolation → ../../lib。
  core_lib = File.expand_path("../../lib", __dir__)

  # E1: root で enable した TracePoint が box 内 :call を観測し、tp.self の
  #     object_id が追跡テーブルと一致する(= 引数プロトコル機構が box を跨ぐ)。
  it "observes box-internal :call from a root TracePoint with matching tp.self identity" do
    box = Ruby::Box.new
    box.eval("class Callee; def ping(x) = x.touch; end")

    probe = Object.new
    def probe.touch = :touched
    tracking = [probe.object_id] # 追跡中テーブル(ArgumentTable 相当)

    seen = []
    matched = nil
    tp = TracePoint.new(:call) do |t|
      seen << t.method_id
      matched ||= tracking.include?(t.self.object_id) if t.method_id == :touch
    end
    tp.enable { box.eval("Callee").new.ping(probe) }

    expect(seen).to include(:touch)
    expect(matched).to be(true)
  end

  # E2: root から box 内定数へアクセスする2手段がどちらも機能する。
  it "exposes box constants to root via box.eval and box::Const" do
    box = Ruby::Box.new
    box.eval("class Widget; def kind = :box_widget; end")

    expect(box.eval("Widget").new.kind).to eq(:box_widget)
    expect(box::Widget.new.kind).to eq(:box_widget)
  end

  # E3: root オブジェクトを box メソッドへ渡すと root 定義で実行され、
  #     Thread-local は同一スレッドなら box を跨いで可視(= 再入ガードが越境で有効)。
  it "runs a root object's method in root space and shares Thread-locals across the box" do
    collector = Object.new
    collector.instance_variable_set(:@space, "root-defined")
    def collector.record = [@space, Thread.current[:ethotrace_probe_flag]]

    box = Ruby::Box.new
    box.eval("class Bridge; def run(c) = c.record; end")

    Thread.current[:ethotrace_probe_flag] = :set_in_root
    space, flag = box.eval("Bridge").new.run(collector)

    expect(space).to eq("root-defined")
    expect(flag).to eq(:set_in_root)
  ensure
    Thread.current[:ethotrace_probe_flag] = nil
  end

  # E4: box にロードした Ethotrace::Tracker が root と別実体になるか。
  #
  # 重要な発見: これは「現在の box の系譜」に依存する(docs/box-semantics.md 参照)。
  #   - main box から作った子 box は ethotrace を独自にロードし実体分離する(汚染解決)。
  #   - 既に ethotrace をロード済みの非 main box(例: RUBY_BOX=1 下の RSpec ランナーは
  #     `#<Ruby::Box:_,root>` で動く)の子 box は、親の定義を共有し分離しない。
  # 自己適用(BoxIsolation, feature 4)はこのロード順依存を制御する必要がある。
  it "separates Ethotrace in a child box only when created from the main box" do
    box = Ruby::Box.new
    box.load_path.unshift(core_lib)
    box.require("ethotrace")
    box_tracker_id = box.eval("Ethotrace::Tracker.object_id")

    if Ruby::Box.current.main?
      expect(box_tracker_id).not_to eq(Ethotrace::Tracker.object_id)
    else
      expect(box_tracker_id).to eq(Ethotrace::Tracker.object_id)
    end
  end

  # E5: root 側で core クラスに張った prepend フックが box 内コードから見えるか。
  #
  # これも box 系譜に依存する。main box の子 box は core クラスの独自ビューを持ち
  # root の prepend が見えない → Requirements / Success・Error 用フックは probe 側
  # (box 内)に張る必要がある(probe 必須性の裏取り)。非 main box の子 box では
  # root prepend が波及する。いずれにせよ probe 側でフックを張れば全系譜で正しく動く。
  it "exposes a root prepend hook to a child box only outside the main box" do
    hits = []
    hook = Module.new do
      define_method(:now) do
        hits << :root_hook_fired
        super()
      end
    end
    Time.singleton_class.prepend(hook)

    box = Ruby::Box.new
    box.eval("def read_time = Time.now")
    box.eval("read_time")

    if Ruby::Box.current.main?
      expect(hits).to be_empty
    else
      expect(hits).to include(:root_hook_fired)
    end
  end
end
