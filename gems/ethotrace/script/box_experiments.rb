# frozen_string_literal: true

# Ruby::Box セマンティクス検証実験(設計資料 v2 §4.8 の E1〜E6)。
#
# Ethotrace の自己適用(self-hosting)では、観測者と観測対象が同一クラス実体を
# 共有して汚染する。これを Ruby::Box(Ruby 4.0 experimental)で実体分離する設計の
# 前提を、実環境で裏取りするための実験ハーネス。
#
# 実行(Ruby >= 4.0):
#
#     RUBY_BOX=1 ruby gems/ethotrace/script/box_experiments.rb
#
# RUBY_BOX=1 が無いと Ruby::Box.new は無効化されるため、結果は記録できない。
# このスクリプトの結論は docs/box-semantics.md に転記する(検証 Ruby バージョンを明記)。

unless defined?(Ruby::Box) && Ruby::Box.enabled?
  warn "Ruby::Box が無効です。RUBY_BOX=1 を付けて Ruby >= 4.0 で実行してください。"
  warn "  例: RUBY_BOX=1 ruby #{$PROGRAM_NAME}"
  exit 1
end

require "objspace"

LIB = File.expand_path("../lib", __dir__)
# E4 で root 側にも Ethotrace を読み込んで box 側と実体比較するため、
# スタンドアロン実行でも root の load path に core の lib を通す。
$LOAD_PATH.unshift(LIB) unless $LOAD_PATH.include?(LIB)

def section(id, title)
  puts "\n== #{id}: #{title} =="
  yield
rescue StandardError => e
  puts "  ! 失敗: #{e.class}: #{e.message}"
end

def result(label, value)
  puts "  #{label}: #{value}"
end

puts "Ruby #{RUBY_VERSION} (#{RUBY_PLATFORM}) / RUBY_BOX=#{ENV["RUBY_BOX"].inspect}"
# 実行中の box の系譜。E4(実体分離)・E5(core クラスの独自ビュー)は、現在の box が
# main box か、既に定義をロード済みの非 main box かで結果が変わる(下の結論参照)。
cur = Ruby::Box.current
puts "current box: #{cur.inspect} main?=#{cur.main?} root?=#{cur.root?}"

# E1: root で enable した TracePoint は box 内の :call を拾うか。
#     拾う場合、tp.self の同一性が追跡テーブルとの突き合わせに使えるか。
section("E1", "root TracePoint が box 内 :call を観測でき、tp.self が同一実体か") do
  box = Ruby::Box.new
  box.eval(<<~RUBY)
    class Callee
      def ping(x) = x.touch
    end
  RUBY

  # root 側で「追跡中テーブル」に登録したオブジェクトを box に渡し、
  # box 内でそのオブジェクトのメソッドを呼ぶ。root の TracePoint が
  # その内側呼び出しを tp.self の同一 object_id で観測できれば、
  # 既存の引数プロトコル機構(ArgumentTable)が box を跨いで機能する。
  probe = Object.new
  def probe.touch = :touched
  tracking = [probe.object_id] # 追跡中テーブル(ArgumentTable 相当)

  seen = []
  matched = nil
  tp = TracePoint.new(:call) do |t|
    seen << t.method_id
    matched ||= tracking.include?(t.self.object_id) if t.method_id == :touch
  end

  tp.enable do
    box.eval("Callee").new.ping(probe)
  end

  result("box 内 :call を観測", seen.inspect)
  result("tp.self が追跡テーブルと一致(同一 object_id)", matched.inspect)
end

# E2: root から box 内の定数・クラス実体へアクセスする公式 API の確定。
section("E2", "box 内定数へのアクセス手段(box.eval / box::Const)") do
  box = Ruby::Box.new
  box.eval("class Widget; def kind = :box_widget; end")

  via_eval =
    begin
      box.eval("Widget").new.kind
    rescue StandardError => e
      "eval 経由失敗: #{e.class}"
    end
  result("box.eval(\"Widget\") 経由", via_eval.inspect)

  via_colon =
    begin
      box::Widget.new.kind
    rescue StandardError => e
      "box::Const 失敗: #{e.class}"
    end
  result("box::Widget 経由", via_colon.inspect)
end

# E3: root のオブジェクト(collector 役)を box 内に渡してメソッドを呼んだとき、
#     どちらの空間の定義で実行されるか。Thread-local 再入ガードは box を
#     跨いでも(同一スレッドなら)有効か。
section("E3", "root オブジェクトのメソッド解決空間と Thread-local の越境") do
  collector = Object.new
  collector.instance_variable_set(:@space, "root-defined")
  def collector.record
    # root 側の定義。Thread-local が box 越しでも見えるかを返す。
    [@space, Thread.current[:ethotrace_probe_flag]]
  end

  # box.eval は locals を取れない(arity 1)ため、box 側に「橋渡しメソッド」を
  # 定義し、root から root オブジェクトを引数で渡して呼ぶ(E1 と同じ越境注入)。
  box = Ruby::Box.new
  box.eval("class Bridge; def run(c); c.record; end; end")

  Thread.current[:ethotrace_probe_flag] = :set_in_root
  space, flag = box.eval("Bridge").new.run(collector)
  result("root オブジェクトのメソッドは root 定義で実行", space.inspect)
  result("Thread-local は box 内から可視", flag.inspect)
ensure
  Thread.current[:ethotrace_probe_flag] = nil
end

# E4: box 内 Ethotrace::Tracker != root Ethotrace::Tracker の実体分離。
section("E4", "box にロードした Ethotrace が root と別実体か(汚染の構造的解決)") do
  require "ethotrace"
  root_tracker_id = Ethotrace::Tracker.object_id

  box = Ruby::Box.new
  box.load_path.unshift(LIB)
  box.require("ethotrace")
  box_tracker_id = box.eval("Ethotrace::Tracker.object_id")

  result("root Ethotrace::Tracker.object_id", root_tracker_id)
  result("box  Ethotrace::Tracker.object_id", box_tracker_id)
  result("実体が分離している(別 object_id)", root_tracker_id != box_tracker_id)
end

# E5: box 内コードの Time.now / ENV[] が box 側ビューのクラスを解決するか。
#     root 側で prepend したフックが box 内から見えなければ、probe 側フックが必須。
section("E5", "root の prepend フックが box 内コードから見えるか(probe 必要性の裏取り)") do
  hits = []
  hook = Module.new do
    define_method(:now) do
      hits << :root_hook_fired
      super()
    end
  end
  Time.singleton_class.prepend(hook)

  box = Ruby::Box.new
  box.eval("def read_time; Time.now; end")
  box.eval("read_time")

  result("box 内 Time.now で root フックが発火", hits.include?(:root_hook_fired))
  result("→ 解釈", hits.empty? ? "probe 側フックが必須(box は独自ビュー)" : "root フックが box 内まで波及")
end

# E6: box 1個あたりの生成・メモリオーバーヘッドの概算。
section("E6", "box 生成のオーバーヘッド(時間・メモリ)") do
  GC.start
  before_mem = ObjectSpace.memsize_of_all
  n = 20
  t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  boxes = Array.new(n) do
    b = Ruby::Box.new
    b.eval("class Tiny; end")
    b
  end
  t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  after_mem = ObjectSpace.memsize_of_all

  result("box 生成数", n)
  result("1個あたり生成時間(ms)", format("%.3f", (t1 - t0) * 1000 / n))
  result("memsize 増分合計(byte)", after_mem - before_mem)
  result("1個あたり memsize 増分(byte)", (after_mem - before_mem) / n)
  boxes.clear
end

puts "\n完了。結論を docs/box-semantics.md に転記すること。"
