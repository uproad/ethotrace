# frozen_string_literal: true

# 自己適用(self-hosting)E2E ハーネス(設計資料 v2 §4.8 / §9 M5)。
#
# 「Ruby で書かれた Ruby 解析器は自身も解析可能であるべき」を実証する。BoxIsolation
# (Isolation::Box)で子 box に Ethotrace を新規ロードし、box 内の Ethotrace 自身の
# メソッドを観測対象として計装する。観測イベントは root の Collector / JSONL ライター
# まで橋渡しされ、**Ethotrace 自身の観測レコード**が得られる。
#
# 観測者(root の Tracker / 帰属 / Writer)と観測対象(box 内 Ethotrace コピー)は
# 別 box の別実体なので、計装機構が計装対象になる自己言及汚染は構造的に起きない。
# さらに記録の活性パス(Tracker/Wrapper/…)は deny-list(Wrapper::SELF_DENY_LIST)で
# 二重に保護され、box 内でも誤計装されない。
#
# 実行(Ruby >= 4.0):
#
#     RUBY_BOX=1 ruby gems/ethotrace/script/self_hosting.rb
#
# RUBY_BOX=1 が無い、または非 main box(例: bundle exec 配下)では子 box が分離しない
# ため、main box からのスタンドアロン起動を要求する。出力 JSONL は tmp/ethotrace 配下。

require "json"

LIB = File.expand_path("../lib", __dir__)
$LOAD_PATH.unshift(LIB) unless $LOAD_PATH.include?(LIB)
require "ethotrace"

unless Ethotrace::Isolation::Box.available?
  warn "Ruby::Box が無効です。RUBY_BOX=1 を付けて Ruby >= 4.0 で実行してください。"
  warn "  例: RUBY_BOX=1 ruby #{$PROGRAM_NAME}"
  exit 1
end

unless Ruby::Box.current.main?
  warn "main box から起動してください(非 main box の子 box は親定義を共有し分離しません)。"
  warn "  bundle exec などの配下ではなく、素の `RUBY_BOX=1 ruby #{$PROGRAM_NAME}` で実行すること。"
  exit 1
end

OUT_PATH = File.expand_path("../../../tmp/ethotrace/self-hosting.jsonl", __dir__)

# root 側に本物の観測パイプラインを用意する(session レコード + 自己観測を JSONL 出力)。
writer = Ethotrace::JSONLWriter.open(OUT_PATH, session: "self-hosting-pid#{Process.pid}",
                                               adapters: [], options: {})
Ethotrace::Collector.subscribe(writer)

# BoxIsolation で probe を子 box に閉じ込める(box 内へ Ethotrace を新規ロード)。
strategy = Ethotrace::Isolation::Box.new
strategy.install_probe(Ethotrace::AdapterRegistry)
box = strategy.box
bridge = box.eval("Ethotrace::Isolation::BoxBridge")

# 観測対象: box 内 Ethotrace 自身の Merge(記録パス外なので deny-list を通る)の
# 公開特異メソッド群。call の内部で accumulate→merge_into→build が走るため、
# 一回の Merge.call で複数の自己観測が得られる。
target_methods = box.eval("Ethotrace::Merge.singleton_methods(false).map(&:to_s)")
wrapped = target_methods.select { |m| bridge.wrap("Ethotrace::Merge", m, kind: :singleton) }

puts "Ruby #{RUBY_VERSION} / main box=#{Ruby::Box.current.main?}"
puts "box Ethotrace separated from root? " \
     "#{box.eval("Ethotrace::Tracker.object_id") != Ethotrace::Tracker.object_id}"
puts "wrapped box-side Ethotrace::Merge methods: #{wrapped.sort.inspect}"
puts "deny-list still protects box-side recording path? " \
     "#{box.eval("Ethotrace::Wrapper.self_denied?(Ethotrace::Tracker)")}"

# box 内で Ethotrace 自身を動かす(2 セッション分の観測を Merge で統合)。
merged = box.eval(<<~INNER)
  observations = [
    { method: { owner: "Cart", name: "total", kind: "instance" },
      return: { classes_seen: ["Integer"] },
      errors: [], requirements: [{ kind: "env.read", write: false, direct: true, detail: { key: "TAX" } }],
      samples: 3, session: "w1" },
    { method: { owner: "Cart", name: "total", kind: "instance" },
      return: { classes_seen: ["Float"] },
      errors: [{ class: "KeyError", origin: "inherited", from: "Hash#fetch" }],
      requirements: [], samples: 2, session: "w2" }
  ]
  Ethotrace::Merge.call(observations)
INNER

strategy.uninstall_probe(Ethotrace::AdapterRegistry)
Ethotrace::Collector.unsubscribe(writer)
writer.close

puts "\nbox Merge.call merged #{merged.size} record(s) (behavior unchanged)."
puts "self-observations written to #{OUT_PATH}"

# 出力された method_observation だけを読み戻し、得られた Ethotrace 自身の規約を要約表示する。
records = File.readlines(OUT_PATH).map { |line| JSON.parse(line, symbolize_names: true) }
self_obs = records.select { |r| r[:type] == "method_observation" }
puts "\n== Ethotrace 自身の観測された規約(observed contract)=="
self_obs.map { |r| [r[:method], r.dig(:return, :classes_seen)] }
        .uniq
        .sort_by { |method, _| method.values_at(:owner, :name) }
        .each { |method, returns| puts "  #{method[:owner]}##{method[:name]} -> #{Array(returns).inspect}" }
