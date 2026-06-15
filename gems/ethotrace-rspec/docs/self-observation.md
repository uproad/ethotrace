# 自己観測レポート — ethotrace-rspec

Ethotrace を **この gem 自身のテストスイートに適用** して得た観測結果。公開メソッド
について、テスト実行中に観測された **戻り値の型・伝播例外・実行環境要件(Requirements)・
引数プロトコル** を記録したもの。

> **これは observed contract(観測された下限)である。** テストで実行されたパスだけが
> 反映され、未実行パスの規約は含まれない。これは欠陥ではなく仕様(`CLAUDE.md` /
> 設計資料 §「観測結果の重要な仕様」)。
>
> このマークダウンは要約であり、**機械可読な観測データ本体は同梱の
> [`self-observation.jsonl`](./self-observation.jsonl)**(schema v1 の
> method_observation レコード列)。MCP の `ethotrace-mcp` でそのまま読み込める。
> `script/dogfood/report.rb` で再生成できる。

## 観測環境

| 項目 | 値 |
|---|---|
| gem | ethotrace-rspec |
| Ruby | 4.0.3 |
| Ethotrace | 0.1.0 |
| スキーマ | v1 |
| アダプタ | stdlib, rspec-targets |
| `trace_c_call` | false |
| `record_sql_source` | false |
| 観測メソッド数 | 9 |

## 観測範囲と制約

自己観測には固有の制約があり、観測対象は **「観測に関与しないオフラインのデータ処理層・
純クエリ層」に限定** している。

- **観測エンジン本体(`Wrapper` / `Tracker` / `Session` / `TracePoint` 等)はこの
  NullIsolation の dogfood では対象外。** 計装機構そのものを計装すると、ラップ呼び出しが
  共有スタックや購読者をテスト中に変化させてエンジン自身の単体テストを壊し、自己言及で
  `SystemStackError` に至る。エンジン内部は **BoxIsolation で別実体に隔離して観測**する
  (設計資料 §4.8 / `CLAUDE.md` ルール7、`gems/ethotrace/script/self_observe_engine.rb`)。結果は core gem の `docs/self-observation-engine.md` を参照。
  なお記録の活性パス(`Wrapper::SELF_DENY_LIST`)は Box でも観測対象から恒久除外される。
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
cd gems/ethotrace-rspec
ETHOTRACE_DOGFOOD_SESSION=rspec ETHOTRACE_DOGFOOD_OUT=tmp/dogfood \
  bundle exec rspec -r ../../script/dogfood/observe.rb -I spec \
  spec/ethotrace/rspec/configuration_spec.rb
bundle exec ethotrace merge tmp/dogfood/*.jsonl -o docs/self-observation.jsonl
bundle exec ruby ../../script/dogfood/normalize.rb docs/self-observation.jsonl
ETHOTRACE_SELF_GEM=rspec bundle exec ruby ../../script/dogfood/report.rb
```

> 生ログ(`tmp/dogfood/`)は再生成可能なためコミットしない。**正規化済みストア
> `docs/self-observation.jsonl` は観測成果物としてコミットする。** この gem の root を
> 作業ディレクトリにして実行するため、`site.path` は **この gem 相対**(`lib/...`)で
> 記録される(core が観測時点で `Ethotrace::PathNormalizer` で相対化)。normalize は
> core が相対化できない base 外のパス(io が触れた gem リソース・tmp ファイル)の
> 畳み込みと、session_id・レコード順の決定化のみを担う。

## 観測契約

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

- **純メソッド(R=∅ かつ 伝播例外=∅): 8 / 9。** 観測された範囲では副作用も伝播例外も持たない。
- **非決定性の疑い(`time.read` / `random.read`): 0 件。**
- **Requirements を記録したメソッド: 1 件。** 観測された語彙: `env.read`。
- **伝播例外: 0 件。** テストはおおむね正常系を通すため、例外パスは未到達。これは observed contract が下限であることの具体例。

---

*このファイルは `script/dogfood/report.rb` が `docs/self-observation.jsonl` から生成した。観測の取り方は上記「再現手順」を参照。*
