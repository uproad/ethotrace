# frozen_string_literal: true

# エンジン本体の自己観測ハーネス(BoxIsolation / 設計資料 v2 §4.8 / §9 M5)。
#
#   RUBY_BOX=1 ruby gems/ethotrace/script/self_observe_engine.rb
#
# RSpec ベースの dogfood(script/dogfood)は NullIsolation で動くため、観測機構そのもの
# (Wrapper/Tracker/Session/…)を観測すると自己言及で壊れる。本ハーネスは Ruby::Box で
# **観測器(root)と観測対象(box 内 Ethotrace の別実体)を分離**し、box 側エンジン内部を
# 安全に観測する。観測イベントは root の Collector へ橋渡しされ、core 自身の Merge で
# 集約される(自己適用)。
#
# 観測できるのは **記録の活性パス以外**のエンジン内部に限る。Tracker / Wrapper /
# Collector / Instrumentation 等は box を跨いでも記録中に走るため `Wrapper::SELF_DENY_LIST`
# が常時除外する(設計 §4.8 defense-in-depth)。本ハーネスはその拒否も実証する。
#
# 成果物: gems/ethotrace/docs/self-observation-engine.{jsonl,md}(決定的・再生成可能)。

require "json"
require "tmpdir"
require "fileutils"

LIB = File.expand_path("../lib", __dir__)
GEM_DIR = File.expand_path("..", __dir__)
# 出力先は既定で gem 配下の docs。spec などはコミット済み成果物を汚さないよう ENV で差し替える。
DOC_JSONL = ENV.fetch("ETHOTRACE_ENGINE_JSONL", File.join(GEM_DIR, "docs", "self-observation-engine.jsonl"))
DOC_MD = ENV.fetch("ETHOTRACE_ENGINE_MD", File.join(GEM_DIR, "docs", "self-observation-engine.md"))
HOME = File.expand_path(Dir.home)
TMP = File.expand_path(Dir.tmpdir)

$LOAD_PATH.unshift(LIB) unless $LOAD_PATH.include?(LIB)
require "ethotrace"

unless Ethotrace::Isolation::Box.available? && Ruby::Box.current.main?
  warn "BoxIsolation には Ruby >= 4.0 + RUBY_BOX=1 + main box が必要です。"
  warn "  例: RUBY_BOX=1 ruby #{$PROGRAM_NAME}"
  exit 1
end

# root 側 sink: box から橋渡しされた CallContext のうち Ethotrace 自身のメソッドの
# 観測(to_observation = Merge.call が解する内部フォーマット)だけを集める。
captured = []
sink = lambda do |context|
  observation = context.to_observation
  captured << observation if observation[:method][:owner].to_s.start_with?("Ethotrace::")
end
Ethotrace::Collector.subscribe(sink)

# box に stdlib アダプタを install させ、box 側の Requirements(io.write 等)を観測する。
Ethotrace::AdapterRegistry.register(Ethotrace::Adapters::Stdlib.new)
strategy = Ethotrace::Isolation::Box.new
strategy.install_probe(Ethotrace::AdapterRegistry)
box = strategy.box
box.eval("Ethotrace.base_dir = #{GEM_DIR.inspect}") # site.path を gem 相対(lib/...)へ
bridge = box.eval("Ethotrace::Isolation::BoxBridge")

# 観測対象: deny-list 外のエンジン内部の **公開 API**。box 側の別実体に prepend を張る。
# これらは記録機構に使われるため、Null の dogfood では観測セッション自身と干渉して
# 観測できない(Box で別実体にして初めて安全に観測できる)。
TARGETS = {
  singleton: {
    "Ethotrace::Merge" => %w[call],
    "Ethotrace::JSONLWriter" => %w[open],
    "Ethotrace::AdapterRegistry" => %w[register names adapters reset!]
  },
  instance: {
    "Ethotrace::JSONLWriter" => %w[close closed?],
    "Ethotrace::Instrumenter" => %w[wrap_method]
  }
}.freeze

wrapped = []
TARGETS.each do |kind, classes|
  classes.each do |cls, methods|
    methods.each { |m| wrapped << "#{cls}##{m} (#{kind})" if bridge.wrap(cls, m, kind: kind) }
  end
end

# defense-in-depth の実証: 記録の活性パス(deny-list)は box でも wrap を拒否される。
denied = Ethotrace::Wrapper::SELF_DENY_LIST.reject do |cls|
  bridge.wrap(cls, "object_id", kind: :singleton)
end

# box 内で deny-list 外エンジン内部を実際に動かす(構築した引数で直接 exercise する。
# nested Session は走らせない: 記録 sink の自己 wrap による RootSink 再帰を避けるため)。
probe_dir = Dir.mktmpdir("ethotrace-engine")
# box へは ENV(プロセス共有)で probe パスを渡し、eval 文字列に補間を持ち込まない。
ENV["ETHOTRACE_ENGINE_PROBE"] = File.join(probe_dir, "probe.jsonl")
box.eval(<<~INNER)
  observations = [
    { method: { owner: "Cart", name: "total", kind: "instance" },
      return: { classes_seen: ["Integer"] }, errors: [], requirements: [], params: [], samples: 3, session: "w1" },
    { method: { owner: "Cart", name: "total", kind: "instance" },
      return: { classes_seen: ["Float"] }, errors: [], requirements: [], params: [], samples: 2, session: "w2" }
  ]
  Ethotrace::Merge.call(observations)

  writer = Ethotrace::JSONLWriter.open(ENV.fetch("ETHOTRACE_ENGINE_PROBE"),
                                       session: "engine-self", adapters: [], options: {})
  writer.closed?
  writer.close

  Ethotrace::AdapterRegistry.reset!
  Ethotrace::AdapterRegistry.register(Ethotrace::Adapters::Stdlib.new)
  Ethotrace::AdapterRegistry.names
  Ethotrace::AdapterRegistry.adapters
  Ethotrace::AdapterRegistry.reset!

  toy = Class.new { def noop = 1 }
  Ethotrace::Instrumenter.new.wrap_method(toy, :noop, kind: :instance)
INNER

strategy.uninstall_probe(Ethotrace::AdapterRegistry)
Ethotrace::Collector.unsubscribe(sink)
ENV.delete("ETHOTRACE_ENGINE_PROBE")
FileUtils.remove_entry(probe_dir)

# --- 集約(engine 自身の Merge を使う)と公開用の正規化 ---

# tmp は Dir.mktmpdir のランダムな第一成分を落として決定的な末尾(`tmp:probe.jsonl`)に畳む。
def collapse_tmp(expanded)
  tail = expanded.delete_prefix("#{TMP}/").split("/", 2)[1]
  "tmp:#{tail || File.basename(expanded)}"
end

# base 外の絶対パスを可搬な形へ畳む(site.path は box base_dir で相対化済み)。
def portable_path(path)
  return path unless path.is_a?(String) && path.start_with?("/")

  expanded = File.expand_path(path)
  return "gem:#{expanded.split("/gems/").last}" if expanded.include?("/gems/")
  return collapse_tmp(expanded) if expanded.start_with?("#{TMP}/")
  return "~/#{expanded.delete_prefix("#{HOME}/")}" if expanded.start_with?("#{HOME}/")

  path
end

def relativize_io(record)
  Array(record[:requirements]).each do |req|
    detail = req[:detail]
    detail[:path] = portable_path(detail[:path]) if detail.is_a?(Hash) && detail[:path]
  end
  record
end

merged = Ethotrace::Merge.call(captured).map { |record| relativize_io(record) }

FileUtils.mkdir_p(File.dirname(DOC_JSONL))
File.open(DOC_JSONL, "w") { |io| merged.each { |record| io.puts(JSON.generate(record)) } }

# --- マークダウン生成 ---
def short(owner) = owner.sub("Ethotrace::", "")

def sig(record)
  m = record[:method]
  "#{short(m[:owner])}#{m[:kind] == "singleton" ? "." : "#"}#{m[:name]}"
end

rows = merged.sort_by { |record| sig(record) }
out = +""
out << <<~HEADER
  # 自己観測レポート — ethotrace エンジン内部(BoxIsolation)

  Ethotrace を **Ruby::Box で隔離して自分自身のエンジン内部に適用**して得た観測結果。
  RSpec ベースの dogfood([self-observation.md](./self-observation.md))は NullIsolation で
  動くため観測機構そのものを観測できないが、本レポートは **BoxIsolation**(設計資料 §4.8 /
  §9 M5)で観測器(root)と観測対象(box 内 Ethotrace の別実体)を分離し、エンジン内部を
  安全に観測する。集約には core 自身の `Ethotrace::Merge` を使う(自己適用)。

  > **これは observed contract(観測された下限)である。** 実行したパスだけが反映される。
  > 機械可読データ本体は同梱の [`self-observation-engine.jsonl`](./self-observation-engine.jsonl)
  > (schema v#{Ethotrace::SCHEMA_VERSION})。`gems/ethotrace/script/self_observe_engine.rb` で再生成できる。

  ## 観測環境

  | 項目 | 値 |
  |---|---|
  | Ruby | #{RUBY_VERSION}(`RUBY_BOX=1` / main box) |
  | Ethotrace | #{Ethotrace::VERSION} |
  | スキーマ | v#{Ethotrace::SCHEMA_VERSION} |
  | 隔離戦略 | BoxIsolation(`Ethotrace::Isolation::Box`) |
  | 観測メソッド数 | #{rows.size} |

  ## なぜ Box が要るか / 何が観測できないか

  - 観測器と観測対象が同一空間にいる NullIsolation では、エンジン内部を観測すると計装機構が
    計装対象になり自己言及で壊れる。Box は box 内 Ethotrace を root と**別実体**にしてこれを断つ
    (`box Tracker.object_id != root Tracker.object_id`)。
  - **記録の活性パスは Box でも観測できない**(恒久的な床)。`Wrapper::SELF_DENY_LIST` が
    box を跨いでも次を計装対象から除外する(設計 §4.8 defense-in-depth):
    #{denied.map { |c| "`#{short(c)}`" }.join(" / ")}。
    本ハーネスでこれらの wrap が実際に拒否されることを確認している。

  ## 観測契約(エンジン内部)

  観測メソッド: #{rows.size}

  | メソッド | 戻り値の型 | Requirements | 伝播例外 | samples |
  |---|---|---|---|---|
HEADER

rows.each do |record|
  returns = Array(record.dig(:return, :classes_seen)).join(" \\| ")
  reqs = Array(record[:requirements]).map { |r| r[:kind] }.uniq.sort
  errs = Array(record[:errors]).map { |e| e[:class] }.uniq.sort
  out << "| `#{sig(record)}` | #{returns} | #{reqs.empty? ? "—" : reqs.map { |r| "`#{r}`" }.join(", ")} | " \
         "#{errs.empty? ? "—" : errs.join(", ")} | #{record[:samples]} |\n"
end

out << <<~FINDINGS

  ## 所見

  - **エンジン内部 #{rows.size} メソッドの規約を、自己言及で壊さずに観測できた。** これは
    BoxIsolation がなければ得られない(Null の dogfood では観測機構を観測できない)。
  - **`JSONLWriter.open` は `io.write` / `time.read` を要求する**(Ethotrace が自身の出力シンクの Requirements を観測した例)。
  - **deny-list の床は健在。** 記録の活性パス(#{denied.size} クラス)は Box でも wrap を拒否され、
    自己観測の対象にならない。これは欠陥ではなく設計(§4.8)。

  ---

  *このファイルは `gems/ethotrace/script/self_observe_engine.rb` が生成した。*
FINDINGS

File.write(DOC_MD, out)

puts "wrapped box-side engine methods: #{wrapped.size}"
puts "deny-list refused (engine recording path): #{denied.map { |c| short(c) }.inspect}"
puts "wrote #{DOC_JSONL} (#{merged.size} methods)"
puts "wrote #{DOC_MD}"
