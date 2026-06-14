# 自己観測レポート(Ethotrace dogfooding)

Ethotrace を **Ethotrace 自身のテストスイートに適用** して得た観測結果。各 gem の
公開メソッドについて、テスト実行中に観測された **戻り値の型・伝播例外・実行環境要件
(Requirements)・引数プロトコル** を記録したもの。

> **これは observed contract(観測された下限)である。** テストで実行されたパスだけが
> 反映され、未実行パスの規約は含まれない。これは欠陥ではなく仕様(`CLAUDE.md` /
> 設計資料 §「観測結果の重要な仕様」)。本レポートは手動生成の成果物で、
> `script/dogfood/report.rb` で再生成できる。

## 観測環境

| 項目 | 値 |
|---|---|
| Ruby | 4.0.3 |
| Ethotrace | 0.1.0 |
| スキーマ | v1 |
| アダプタ | stdlib, rspec-targets |
| `trace_c_call` | false |
| `record_sql_source` | false |
| 観測セッション数 | 3 |
| 観測メソッド数 | 40 |

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
bundle exec rspec -r ./script/dogfood/observe.rb -I gems/ethotrace/spec \
  gems/ethotrace/spec/ethotrace/merge_spec.rb gems/ethotrace/spec/ethotrace/cli
bundle exec rspec -r ./script/dogfood/observe.rb -I gems/ethotrace-mcp/spec \
  gems/ethotrace-mcp/spec/ethotrace/mcp_spec.rb gems/ethotrace-mcp/spec/ethotrace/mcp
bundle exec rspec -r ./script/dogfood/observe.rb -I gems/ethotrace-rspec/spec \
  gems/ethotrace-rspec/spec/ethotrace/rspec/configuration_spec.rb

# 2. マージして 1 つのストアへ
bundle exec ethotrace merge tmp/dogfood/*.jsonl -o ethotrace/self-observation.jsonl

# 3. 本ドキュメントを再生成
bundle exec ruby script/dogfood/report.rb
```

> 生 JSONL(`tmp/dogfood/`)とマージ済みストア(`ethotrace/`)は再生成可能なため
> コミットしない(`.gitignore` 済み)。コミットするのは本マークダウンと生成スクリプトのみ。

## gem 別の観測契約

### ethotrace(core)

観測メソッド: 8

| メソッド | 戻り値の型 | Requirements | 伝播例外 | samples |
|---|---|---|---|---|
| `CLI::Aggregator.call` | Array | — | — | 21 |
| `CLI::Color#paint` | String | — | — | 54 |
| `CLI::MergeCommand#run` | Integer | `io.write` | — | 7 |
| `CLI::Reader#read` | Ethotrace::CLI::Reader::Result | — | — | 26 |
| `CLI::Renderer#detail` | NilClass | — | — | 6 |
| `CLI::Renderer#summary` | NilClass | — | — | 3 |
| `CLI::ViewCommand#run` | Integer | — | — | 13 |
| `Merge.call` | Array | — | — | 18 |

**観測された引数プロトコル**(引数に対して呼ばれたメソッド集合 = 要求されるダックタイプ):

- `CLI::Renderer#detail`: `observation` → `id`

### ethotrace-mcp

観測メソッド: 23

| メソッド | 戻り値の型 | Requirements | 伝播例外 | samples |
|---|---|---|---|---|
| `MCP::CLI.start` | Integer | `env.read`, `io.read`, `time.read` | — | 3 |
| `MCP::Catalog#exceptions_of` | Array \| NilClass | — | — | 3 |
| `MCP::Catalog#flaky_suspects` | Array | — | — | 3 |
| `MCP::Catalog#lookup` | Hash \| NilClass | — | — | 12 |
| `MCP::Catalog#methods` | Array | — | — | 3 |
| `MCP::Catalog#param_protocol` | Array \| NilClass | — | — | 3 |
| `MCP::Catalog#pure_methods` | Array | — | — | 2 |
| `MCP::Catalog#raisers` | Array | — | — | 3 |
| `MCP::Catalog#requiring` | Array | — | — | 2 |
| `MCP::Catalog.load` | Ethotrace::MCP::Catalog | — | — | 3 |
| `MCP::Server.build` | MCP::Server | `env.read`, `io.read` | — | 12 |
| `MCP::Stdio.run` | StringIO | `time.read` | — | 5 |
| `MCP::Tools.exceptions_of` | NilClass | — | — | 12 |
| `MCP::Tools.flaky_suspects` | NilClass | `io.read` | — | 12 |
| `MCP::Tools.install` | NilClass | `env.read`, `io.read` | — | 12 |
| `MCP::Tools.list_methods` | NilClass | `io.read` | — | 12 |
| `MCP::Tools.lookup_method` | NilClass | `env.read`, `io.read` | — | 12 |
| `MCP::Tools.method_args` | Hash | — | — | 3 |
| `MCP::Tools.methods_raising` | NilClass | `io.read` | — | 12 |
| `MCP::Tools.param_protocol` | NilClass | `io.read` | — | 12 |
| `MCP::Tools.pure_methods` | NilClass | — | — | 12 |
| `MCP::Tools.requiring` | NilClass | `io.read` | — | 12 |
| `MCP::Tools.respond` | MCP::Tool::Response | — | — | 7 |

**観測された引数プロトコル**(引数に対して呼ばれたメソッド集合 = 要求されるダックタイプ):

- `MCP::Stdio.run`: `server` → `accepts_server_context?`, `add_instrumentation_data`, `call_tool`, `call_tool_with_args`, `cursor_from`, `dispatch_optional_context_handler`, `handle_json`, `handle_request`, `handler_declares_server_context?`, `instrument_call`, `list_tools`, `paginate`, `server_context_with_meta`, `validate_tool_call_result!`
- `MCP::Tools.exceptions_of`: `server` → `define_tool`, `validate!`, `validate_tool_name!`
- `MCP::Tools.flaky_suspects`: `server` → `define_tool`, `validate!`, `validate_tool_name!`
- `MCP::Tools.install`: `server` → `define_tool`, `validate!`, `validate_tool_name!`
- `MCP::Tools.list_methods`: `server` → `define_tool`, `validate!`, `validate_tool_name!`
- `MCP::Tools.lookup_method`: `server` → `define_tool`, `validate!`, `validate_tool_name!`
- `MCP::Tools.methods_raising`: `server` → `define_tool`, `validate!`, `validate_tool_name!`
- `MCP::Tools.param_protocol`: `server` → `define_tool`, `validate!`, `validate_tool_name!`
- `MCP::Tools.pure_methods`: `server` → `define_tool`, `validate!`, `validate_tool_name!`
- `MCP::Tools.requiring`: `server` → `define_tool`, `validate!`, `validate_tool_name!`

### ethotrace-rspec

観測メソッド: 9

| メソッド | 戻り値の型 | Requirements | 伝播例外 | samples |
|---|---|---|---|---|
| `RSpec::Configuration#adapters` | Array | — | — | 2 |
| `RSpec::Configuration#observe` | Ethotrace::RSpec::Configuration | — | — | 3 |
| `RSpec::Configuration#options` | Hash | — | — | 1 |
| `RSpec::Configuration#output_dir` | String | — | — | 1 |
| `RSpec::Configuration#output_dir=` | String | — | — | 1 |
| `RSpec::Configuration#output_path` | String | — | — | 1 |
| `RSpec::Configuration#session_id` | String | `env.read` | — | 4 |
| `RSpec::Configuration#session_id=` | String | — | — | 2 |
| `RSpec::Configuration#targets` | Array | — | — | 3 |

## 横断的な所見

- **純メソッド(R=∅ かつ 伝播例外=∅): 28 / 40。**
  観測された範囲では副作用も伝播例外も持たない。`MCP::Catalog` のクエリ群はすべてここに入り、
  純クエリ層という設計意図が観測でも裏づけられた。
- **非決定性の疑い(`time.read` / `random.read`): 2 件。**
  `MCP::CLI.start`, `MCP::Stdio.run`。
  セッション ID 生成や stdio ループのタイムスタンプ取得が源泉で、いずれも妥当。
- **Requirements を記録したメソッド: 12 件。** `io.read` / `env.read` /
  `io.write` / `time.read`。多くは MCP サーバ構築時のカタログ読み込み(ファイル IO・ENV 参照)が
  コールスタックを通じて帰属したもの。
- **伝播例外: 0 件。** テストはおおむね正常系を通すため、例外パスは未到達。これは
  observed contract が下限であることの具体例。例外規約を観測するにはエラーパスを通す
  テストが要る。
- **引数プロトコルの収穫の例**: `MCP::Stdio.run` は引数 `server` に対して
  `handle_json` をはじめとする一連のメソッドが呼ばれたことを記録した。これは Ethotrace が
  公称型ではなく「実際に要求された振る舞い(プロトコル)」を捉える狙いそのもの。

---

*このファイルは `script/dogfood/report.rb` が `ethotrace/self-observation.jsonl` から生成した。観測の取り方は
上記「再現手順」を参照。*
