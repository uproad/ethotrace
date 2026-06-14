# frozen_string_literal: true

# 1 つの gem の正規化済み自己観測 JSONL から、その gem の `docs/self-observation.md` を
# 生成する。出力は決定的(常にソート)なので、再観測 → 再生成で差分が安定する。
#
#   cd gems/<gem>
#   ETHOTRACE_SELF_GEM=<core|mcp|rspec> bundle exec ruby ../../script/dogfood/report.rb
#
# 観測環境(Ruby/Ethotrace の版・options 等)はマージ済みストアには残らないため、
# 生ログ(`ETHOTRACE_DOGFOOD_OUT`)の session レコードから補完する。観測の取り方は
# script/dogfood/observe.rb のヘッダ、または駆動スクリプト script/dogfood/generate.sh を参照。

require "json"

STORE = ENV.fetch("ETHOTRACE_SELF_STORE", "docs/self-observation.jsonl")
OUT = ENV.fetch("ETHOTRACE_SELF_DOC", "docs/self-observation.md")
GEM = ENV.fetch("ETHOTRACE_SELF_GEM", "core")
RAW_DIR = ENV.fetch("ETHOTRACE_DOGFOOD_OUT", "tmp/dogfood")

GEM_META = {
  "core" => {
    title: "ethotrace(core)",
    dir: "gems/ethotrace",
    specs: "spec/ethotrace/merge_spec.rb spec/ethotrace/cli"
  },
  "mcp" => {
    title: "ethotrace-mcp",
    dir: "gems/ethotrace-mcp",
    specs: "spec/ethotrace/mcp_spec.rb spec/ethotrace/mcp"
  },
  "rspec" => {
    title: "ethotrace-rspec",
    dir: "gems/ethotrace-rspec",
    specs: "spec/ethotrace/rspec/configuration_spec.rb"
  }
}.freeze

META = GEM_META.fetch(GEM)

def short(owner)
  owner.sub("Ethotrace::", "")
end

def sig(rec)
  m = rec["method"]
  sep = m["kind"] == "singleton" ? "." : "#"
  "#{short(m["owner"])}#{sep}#{m["name"]}"
end

def return_classes(rec)
  Array((rec["return"] || {})["classes_seen"]).join(" \\| ")
end

def requirement_kinds(rec)
  Array(rec["requirements"]).map { |r| r["kind"] }.uniq.sort
end

def error_classes(rec)
  Array(rec["errors"]).map { |e| e["class"] }.uniq.sort
end

# プロトコル(引数に対して呼ばれたメソッド集合)が空でない param のみ要約する。
def protocols(rec)
  Array(rec["params"]).filter_map do |p|
    names = Array(p["protocol"]).map { |x| x["name"] }
    next if names.empty?

    label = p["name"] || "arg#{p["position"]}"
    "`#{label}` → #{names.sort.map { |n| "`#{n}`" }.join(", ")}"
  end
end

records = File.readlines(STORE).map { |line| JSON.parse(line) }
methods = records.select { |r| r["type"] == "method_observation" }.sort_by { |r| sig(r) }
sessions = records.select { |r| r["type"] == "session" }
if sessions.empty?
  sessions = Dir["#{RAW_DIR}/*.jsonl"].flat_map do |file|
    File.readlines(file).map { |line| JSON.parse(line) }.select { |r| r["type"] == "session" }
  end
end

env = sessions.first || {}

out = +""
out << <<~HEADER
  # 自己観測レポート — #{META[:title]}

  Ethotrace を **この gem 自身のテストスイートに適用** して得た観測結果。公開メソッド
  について、テスト実行中に観測された **戻り値の型・伝播例外・実行環境要件(Requirements)・
  引数プロトコル** を記録したもの。

  > **これは observed contract(観測された下限)である。** テストで実行されたパスだけが
  > 反映され、未実行パスの規約は含まれない。これは欠陥ではなく仕様(`CLAUDE.md` /
  > 設計資料 §「観測結果の重要な仕様」)。
  >
  > このマークダウンは要約であり、**機械可読な観測データ本体は同梱の
  > [`self-observation.jsonl`](./self-observation.jsonl)**(schema v#{env["schema_version"] || 1} の
  > method_observation レコード列)。MCP の `ethotrace-mcp` でそのまま読み込める。
  > `script/dogfood/report.rb` で再生成できる。

HEADER

out << <<~ENV
  ## 観測環境

  | 項目 | 値 |
  |---|---|
  | gem | #{META[:title]} |
  | Ruby | #{env["ruby_version"]} |
  | Ethotrace | #{env["ethotrace_version"]} |
  | スキーマ | v#{env["schema_version"]} |
  | アダプタ | #{Array(env["adapters"]).join(", ")} |
  | `trace_c_call` | #{(env["options"] || {})["trace_c_call"].inspect} |
  | `record_sql_source` | #{(env["options"] || {})["record_sql_source"].inspect} |
  | 観測メソッド数 | #{methods.size} |

ENV

out << <<~SCOPE
  ## 観測範囲と制約

  自己観測には固有の制約があり、観測対象は **「観測に関与しないオフラインのデータ処理層・
  純クエリ層」に限定** している。

  - **観測エンジン本体(`Wrapper` / `Tracker` / `Session` / `TracePoint` 等)は対象外。**
    計装機構そのものを計装すると、ラップ呼び出しが共有スタックや購読者をテスト中に変化させて
    エンジン自身の単体テストを壊し、自己言及で `SystemStackError` に至る。エンジン本体の
    自己観測は box 隔離(M5)を前提とする別タスク(設計資料 §4.8 / `CLAUDE.md` ルール7)。
  - **`Wrapper.reset!` を呼ぶ spec は除外。** reset! は観測 writer(購読者)を外すため、
    途中から記録が止まる。`ethotrace-mcp` の E2E spec などはこの理由で対象から外している。
  - **C で実装されたメソッドは引数プロトコルに現れない。** 既定の `TracePoint` は
    `:call`(Ruby メソッド)のみを購読し `:c_call` はオプトイン。String を Hash キーに
    使う等の操作は C メソッド経由のため、プロトコルが空(`{}`)になる。
  - **StringIO やモックは Requirements を隠す。** チョークポイント(実 IO / ENV 等)を
    通らないため、テストで `StringIO` を渡すメソッドは `io.write` 等が記録されない。

  ### 再現手順

  この gem の root から、その gem の安全な spec のみを観測下で実行する。詳しくは
  リポジトリルートの `script/dogfood/generate.sh`(全 gem を一括再生成)を参照。

  ```bash
  cd #{META[:dir]}
  ETHOTRACE_DOGFOOD_SESSION=#{GEM} ETHOTRACE_DOGFOOD_OUT=tmp/dogfood \\
    bundle exec rspec -r ../../script/dogfood/observe.rb -I spec \\
    #{META[:specs]}
  bundle exec ethotrace merge tmp/dogfood/*.jsonl -o docs/self-observation.jsonl
  bundle exec ruby ../../script/dogfood/normalize.rb docs/self-observation.jsonl
  ETHOTRACE_SELF_GEM=#{GEM} bundle exec ruby ../../script/dogfood/report.rb
  ```

  > 生ログ(`tmp/dogfood/`)は再生成可能なためコミットしない。**正規化済みストア
  > `docs/self-observation.jsonl` は観測成果物としてコミットする。** この gem の root を
  > 作業ディレクトリにして実行するため、`site.path` は **この gem 相対**(`lib/...`)で
  > 記録される(core が観測時点で `Ethotrace::PathNormalizer` で相対化)。normalize は
  > core が相対化できない base 外のパス(io が触れた gem リソース・tmp ファイル)の
  > 畳み込みと、session_id・レコード順の決定化のみを担う。

SCOPE

out << "## 観測契約\n\n観測メソッド: #{methods.size}\n\n"
out << "| メソッド | 戻り値の型 | Requirements | 伝播例外 | samples |\n"
out << "|---|---|---|---|---|\n"
methods.each do |rec|
  reqs = requirement_kinds(rec)
  errs = error_classes(rec)
  out << "| `#{sig(rec)}` | #{return_classes(rec)} | " \
         "#{reqs.empty? ? "—" : reqs.map { |r| "`#{r}`" }.join(", ")} | " \
         "#{errs.empty? ? "—" : errs.join(", ")} | #{rec["samples"]} |\n"
end
out << "\n"

proto_rows = methods.filter_map do |rec|
  ps = protocols(rec)
  ["`#{sig(rec)}`", ps] unless ps.empty?
end
unless proto_rows.empty?
  out << "**観測された引数プロトコル**(引数に対して呼ばれたメソッド集合 = 要求されるダックタイプ):\n\n"
  proto_rows.each { |sig_label, ps| out << "- #{sig_label}: #{ps.join(" / ")}\n" }
  out << "\n"
end

# 横断的な所見(この gem の観測データから機械的に導く)
pure = methods.select { |r| requirement_kinds(r).empty? && error_classes(r).empty? }
flaky = methods.select { |r| requirement_kinds(r).intersect?(%w[time.read random.read]) }
requiring = methods.reject { |r| requirement_kinds(r).empty? }
req_kinds = requiring.flat_map { |r| requirement_kinds(r) }.uniq.sort
raising = methods.reject { |r| error_classes(r).empty? }
widest = proto_rows.max_by { |(_, ps)| ps.sum { |s| s.count(",") } }

out << "## 横断的な所見\n\n"
out << "- **純メソッド(R=∅ かつ 伝播例外=∅): #{pure.size} / #{methods.size}。** " \
       "観測された範囲では副作用も伝播例外も持たない。\n"
out << if flaky.empty?
         "- **非決定性の疑い(`time.read` / `random.read`): 0 件。**\n"
       else
         "- **非決定性の疑い(`time.read` / `random.read`): #{flaky.size} 件。** " \
           "#{flaky.map { |r| "`#{sig(r)}`" }.sort.join(", ")}。\n"
       end
out << if requiring.empty?
         "- **Requirements を記録したメソッド: 0 件。**\n"
       else
         "- **Requirements を記録したメソッド: #{requiring.size} 件。** " \
           "観測された語彙: #{req_kinds.map { |k| "`#{k}`" }.join(" / ")}。\n"
       end
out << if raising.empty?
         "- **伝播例外: 0 件。** テストはおおむね正常系を通すため、例外パスは未到達。これは " \
           "observed contract が下限であることの具体例。\n"
       else
         "- **伝播例外を観測したメソッド: #{raising.size} 件。**\n"
       end
if widest
  out << "- **引数プロトコルの収穫の例**: #{widest[0]} は #{widest[1].join(" / ")} を記録した。" \
         "これは Ethotrace が公称型ではなく「実際に要求された振る舞い(プロトコル)」を捉える狙いそのもの。\n"
end

out << "\n---\n\n"
out << "*このファイルは `script/dogfood/report.rb` が `#{STORE}` から生成した。観測の取り方は上記「再現手順」を参照。*\n"

File.write(OUT, out)
puts "wrote #{OUT} (#{methods.size} methods)"
