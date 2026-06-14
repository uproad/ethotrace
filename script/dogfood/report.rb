# frozen_string_literal: true

# マージ済みの自己観測 JSONL(`ethotrace/self-observation.jsonl`)から
# `docs/self-observation.md` を生成する。出力は決定的(常にソート)なので、
# 再観測 → 再生成で差分が安定する。
#
#   bundle exec ruby script/dogfood/report.rb
#
# 観測の取り方は docs/self-observation.md の「再現手順」節、または
# script/dogfood/observe.rb のヘッダを参照。

require "json"

STORE = ENV.fetch("ETHOTRACE_SELF_STORE", "ethotrace/self-observation.jsonl")
OUT = ENV.fetch("ETHOTRACE_SELF_DOC", "docs/self-observation.md")

records = File.readlines(STORE).map { |line| JSON.parse(line) }
methods = records.select { |r| r["type"] == "method_observation" }

# マージ済みストアは session ヘッダを畳んでしまうため、観測環境(Ruby/Ethotrace の版・
# options 等)は生ログ(tmp/dogfood/*.jsonl)の session レコードから拾う。
sessions = records.select { |r| r["type"] == "session" }
if sessions.empty?
  sessions = Dir["tmp/dogfood/*.jsonl"].flat_map do |file|
    File.readlines(file).map { |line| JSON.parse(line) }.select { |r| r["type"] == "session" }
  end
end

GEMS = {
  "ethotrace" => { title: "ethotrace(core)", match: ->(o) { !o.start_with?("Ethotrace::MCP", "Ethotrace::RSpec") } },
  "ethotrace-mcp" => { title: "ethotrace-mcp", match: ->(o) { o.start_with?("Ethotrace::MCP") } },
  "ethotrace-rspec" => { title: "ethotrace-rspec", match: ->(o) { o.start_with?("Ethotrace::RSpec") } }
}.freeze

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

def methods_for(methods, matcher)
  methods.select { |r| matcher.call(r["method"]["owner"]) }
         .sort_by { |r| sig(r) }
end

out = +""
out << <<~HEADER
  # 自己観測レポート(Ethotrace dogfooding)

  Ethotrace を **Ethotrace 自身のテストスイートに適用** して得た観測結果。各 gem の
  公開メソッドについて、テスト実行中に観測された **戻り値の型・伝播例外・実行環境要件
  (Requirements)・引数プロトコル** を記録したもの。

  > **これは observed contract(観測された下限)である。** テストで実行されたパスだけが
  > 反映され、未実行パスの規約は含まれない。これは欠陥ではなく仕様(`CLAUDE.md` /
  > 設計資料 §「観測結果の重要な仕様」)。本レポートは手動生成の成果物で、
  > `script/dogfood/report.rb` で再生成できる。

HEADER

env = sessions.first || {}
out << <<~ENV
  ## 観測環境

  | 項目 | 値 |
  |---|---|
  | Ruby | #{env["ruby_version"]} |
  | Ethotrace | #{env["ethotrace_version"]} |
  | スキーマ | v#{env["schema_version"]} |
  | アダプタ | #{Array(env["adapters"]).join(", ")} |
  | `trace_c_call` | #{(env["options"] || {})["trace_c_call"].inspect} |
  | `record_sql_source` | #{(env["options"] || {})["record_sql_source"].inspect} |
  | 観測セッション数 | #{sessions.size} |
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
    通らないため、テストで `StringIO` を渡すメソッドは `io.write` 等が記録されない
    (例: `Renderer#summary` は `@out` へ書くが Requirement 0)。

  ### 再現手順

  ```bash
  # 1. 各 gem の安全な spec を観測下で実行(gem ごとに別ファイルへ出力)
  rm -rf tmp/dogfood && mkdir -p tmp/dogfood
  bundle exec rspec -r ./script/dogfood/observe.rb -I gems/ethotrace/spec \\
    gems/ethotrace/spec/ethotrace/merge_spec.rb gems/ethotrace/spec/ethotrace/cli
  bundle exec rspec -r ./script/dogfood/observe.rb -I gems/ethotrace-mcp/spec \\
    gems/ethotrace-mcp/spec/ethotrace/mcp_spec.rb gems/ethotrace-mcp/spec/ethotrace/mcp
  bundle exec rspec -r ./script/dogfood/observe.rb -I gems/ethotrace-rspec/spec \\
    gems/ethotrace-rspec/spec/ethotrace/rspec/configuration_spec.rb

  # 2. マージして 1 つのストアへ
  bundle exec ethotrace merge tmp/dogfood/*.jsonl -o ethotrace/self-observation.jsonl

  # 3. 本ドキュメントを再生成
  bundle exec ruby script/dogfood/report.rb
  ```

  > 生 JSONL(`tmp/dogfood/`)とマージ済みストア(`ethotrace/`)は再生成可能なため
  > コミットしない(`.gitignore` 済み)。コミットするのは本マークダウンと生成スクリプトのみ。

SCOPE

out << "## gem 別の観測契約\n\n"

GEMS.each_value do |info|
  rows = methods_for(methods, info[:match])
  next if rows.empty?

  out << "### #{info[:title]}\n\n"
  out << "観測メソッド: #{rows.size}\n\n"
  out << "| メソッド | 戻り値の型 | Requirements | 伝播例外 | samples |\n"
  out << "|---|---|---|---|---|\n"
  rows.each do |rec|
    reqs = requirement_kinds(rec)
    errs = error_classes(rec)
    out << "| `#{sig(rec)}` | #{return_classes(rec)} | " \
           "#{reqs.empty? ? "—" : reqs.map { |r| "`#{r}`" }.join(", ")} | " \
           "#{errs.empty? ? "—" : errs.join(", ")} | #{rec["samples"]} |\n"
  end
  out << "\n"

  # 引数プロトコル(ダックタイプの観測)があれば併記する。
  proto_rows = rows.filter_map do |rec|
    ps = protocols(rec)
    ["`#{sig(rec)}`", ps] unless ps.empty?
  end
  next if proto_rows.empty?

  out << "**観測された引数プロトコル**(引数に対して呼ばれたメソッド集合 = 要求されるダックタイプ):\n\n"
  proto_rows.each do |sig_label, ps|
    out << "- #{sig_label}: #{ps.join(" / ")}\n"
  end
  out << "\n"
end

# 横断的な所見
pure = methods.select { |r| requirement_kinds(r).empty? && error_classes(r).empty? }
flaky = methods.select { |r| requirement_kinds(r).intersect?(%w[time.read random.read]) }
requiring = methods.reject { |r| requirement_kinds(r).empty? }

out << <<~FINDINGS
  ## 横断的な所見

  - **純メソッド(R=∅ かつ 伝播例外=∅): #{pure.size} / #{methods.size}。**
    観測された範囲では副作用も伝播例外も持たない。`MCP::Catalog` のクエリ群はすべてここに入り、
    純クエリ層という設計意図が観測でも裏づけられた。
  - **非決定性の疑い(`time.read` / `random.read`): #{flaky.size} 件。**
    #{flaky.map { |r| "`#{sig(r)}`" }.sort.join(", ")}。
    セッション ID 生成や stdio ループのタイムスタンプ取得が源泉で、いずれも妥当。
  - **Requirements を記録したメソッド: #{requiring.size} 件。** `io.read` / `env.read` /
    `io.write` / `time.read`。多くは MCP サーバ構築時のカタログ読み込み(ファイル IO・ENV 参照)が
    コールスタックを通じて帰属したもの。
  - **伝播例外: 0 件。** テストはおおむね正常系を通すため、例外パスは未到達。これは
    observed contract が下限であることの具体例。例外規約を観測するにはエラーパスを通す
    テストが要る。
  - **引数プロトコルの収穫の例**: `MCP::Stdio.run` は引数 `server` に対して
    `handle_json` をはじめとする一連のメソッドが呼ばれたことを記録した。これは Ethotrace が
    公称型ではなく「実際に要求された振る舞い(プロトコル)」を捉える狙いそのもの。

  ---

  *このファイルは `script/dogfood/report.rb` が `#{STORE}` から生成した。観測の取り方は
  上記「再現手順」を参照。*
FINDINGS

File.write(OUT, out)
puts "wrote #{OUT} (#{methods.size} methods, #{sessions.size} sessions)"
