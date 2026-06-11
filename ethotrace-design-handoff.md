# Ethotrace — Ruby動的シグネチャ解析システム 設計引き継ぎ資料

> この文書は設計ディスカッションの成果物であり、Claude Code エージェントによる実装着手のための引き継ぎ資料である。
>
> **プロジェクト名: Ethotrace**
> 語源は `etho-`(ethos = 振る舞い・気質。動物行動学の ethogram に通じる「振る舞いの観測カタログ」の含意)+ `trace`(実行時の動的追跡)。型名(公称型)ではなくインスタンスの振る舞いを実行時に観測する、という本システムの思想を一語で表す。学術語そのものではない造語のため検索一意性も確保される。
>
> 実装開始前に rubygems.org と GitHub org/リポジトリ名の空きを確認すること(`gem info -r ethotrace` 等)。万一衝突する場合の代替候補: Ethograph, Traceogram。

---

## 1. プロジェクト概要

Ruby向けの**動的型検査・シグネチャ解析システム**を作る。

既存ツール(RBS / Sorbet / TypeProf)との違い:

| 観点 | 既存ツール | 本システム |
|---|---|---|
| 型の捉え方 | 公称型(型名)中心 | **構造的(インスタンスに呼ばれるメソッド集合 = プロトコル)中心** |
| 解析方式 | 静的解析が主 | **テスト実行中のメソッド呼び出し監視(動的解析)** |
| 例外 | 扱わない | **メソッドから伝播する例外をシグネチャの一部として記録** |
| 実行コンテキスト | 扱わない | **ENV / IO / DB / 時刻 / 乱数などへの接触を Requirements として記録** |

設計思想は Effect-TS の `Effect<Success, Error, Requirements>` に着想を得た三チャネルモデル:

- **Success**: 戻り値の観測情報(クラス + 戻り値に対するプロトコル)
- **Error**: メソッドの外へ**伝播(エスケープ)した**例外の一覧
- **Requirements**: 実行中に接触した外部世界(ENV, ファイル, ネットワーク, DB, 時刻, 乱数, グローバル状態 等)

最終目的: 「あるメソッドが引数に何を要求するか(プロトコル規約)・何を返すか・どんな例外を出しうるか・どんな実行環境を必要とするか」を、プログラマ・ツール・MCP経由のAIエージェントに提供する。

### 重要な仕様上の立場

- 観測結果は **observed contract(観測された下限)** である。テストカバレッジに依存し、未実行パスの規約は含まれない。これは欠陥ではなく仕様であり、ドキュメント・出力フォーマット双方に明示する。
- 観測データは生に近い形で保存し、解釈(Requirements と Side Effects の区別、インターフェースの命名など)は上位レイヤーで行う。

---

## 2. 用語

| 用語 | 意味 |
|---|---|
| プロトコル (protocol) | あるオブジェクトに対して実際に呼ばれたメソッドシグネチャの集合。例: `[{name: :each, block: true}]` |
| エスケープ例外 | メソッド内部で rescue されず、呼び出し元へ伝播した例外。Error チャネルに記録するのはこれのみ |
| エフェクト (effect) | 外部世界への接触イベント。`env.read` などドット区切りの開かれた語彙で表現 |
| 直接 / 継承 (direct / inherited) | エフェクト・例外が当該メソッド自身で発生したか、callee から伝播・継承されたか |
| エフェクトスパン (effect span) | 上位アダプタ(例: `db.query`)の記録区間。区間中の下位フック(例: socket IO)の発火は子として畳み込むか抑制する |
| セッション | 1回のテスト実行(ワーカー)単位の観測。並列実行ではセッションごとにファイルを吐き、後でマージする |

---

## 3. gem 構成(アダプタ方式)

汎用コア + 用途別アダプタの分割。**core は pure Ruby のみに依存し、Rails にも RSpec にも依存しない。**

```
ethotrace            # core: 観測エンジン + stdlibアダプタ + JSONLライター + マージCLI
ethotrace-rspec      # RSpecライフサイクル接続(session開始/終了、対象選択ヘルパ)
ethotrace-minitest   # Minitest版
ethotrace-rails      # Railtie / ActiveSupport::Notifications購読 / Zeitwerk連携
ethotrace-mcp        # 観測結果を提供するMCPサーバ(観測プロセスとは完全分離)
ethotrace-rbs        # RBS interface への投影(例外・Requirementsは投影不可なので欠落を明記)
```

### core とアダプタの境界

- **core = 観測の物理学**: prepend ラッパー生成、TracePoint エンジン、コールコンテキストスタック、帰属機構、三チャネルのデータモデル、シリアライズとマージ。
- **アダプタ = 意味論**: 計装対象の選択、チョークポイントへのエフェクト種別の割り当て、生データの意味的強化(SQL→テーブル名抽出など)、テストライフサイクル接続。

### dogfooding 原則(必須)

ENV / IO / Time / Random などの stdlib フックも、core 内蔵の「stdlib アダプタ」として**公開プラグインAPI経由で**実装する。core が特権的な裏口を使うことを禁止し、サードパーティアダプタが書ける API であることを常に保証する。

### gem 間の安定契約はデータスキーマ

gem 間の互換性は Ruby API ではなく **JSONL 観測データのスキーマ(`schema_version` 付き)** で担保する。`ethotrace-mcp` や `ethotrace-rbs` は観測プロセスと分離されたデータ消費者であり、原理的には別言語実装も可能な構造とする。

---

## 4. core アーキテクチャ

### 4.1 観測機構はハイブリッド

| チャネル | 機構 | 理由 |
|---|---|---|
| Success(戻り値) / Error(伝播例外) | `Module#prepend` ラッパー | `rescue => e; record(e); raise` でエスケープ例外**だけ**を正確に捕捉できる。TracePoint の `:raise` では内部で rescue された例外と区別困難 |
| 引数プロトコル | `TracePoint`(`:call`, 必要に応じ `:c_call`) | 引数オブジェクトの `object_id` を追跡テーブルに登録し、内側呼び出しの `tp.self` と突き合わせる。`TracePoint#enable(target:)` で範囲を絞り負荷を抑える |
| Requirements | チョークポイントへの prepend フック | 外部世界への出入口は少数なので全数監視が不要。軽量 |

### 4.2 prepend ラッパーの骨格

```ruby
module Ethotrace
  module Wrapper
    def self.wrap(klass, name)
      mod = Module.new do
        define_method(name) do |*args, **kw, &blk|
          ctx = Ethotrace::Tracker.begin_call(klass, name, args, kw, blk)
          begin
            result = super(*args, **kw, &blk)
            ctx.record_return(result)
            result
          rescue Exception => e
            ctx.record_escaped_exception(e)   # Error チャネル
            raise
          ensure
            Ethotrace::Tracker.end_call(ctx)
          end
        end
      end
      klass.prepend(mod)
    end
  end
end
```

注意点:
- `rescue Exception` で捕捉して必ず `raise` し直す(挙動を一切変えない)。ただし `Ethotrace` 自身の内部エラーは握りつぶしてはならず、観測を無効化して警告する fail-safe を設ける。
- キーワード引数・ブロック・`...` 委譲の正確なパススルーをテストで保証する(Ruby 3.x の委譲セマンティクスに注意)。
- 同一メソッドへの二重 wrap を防ぐ(計装レジストリで管理)。

### 4.3 Tracker / CallContext

- 追跡コンテキストスタックは **Thread / Fiber ごと**に持つ(`Thread.current` キー、Fiber 安全性を確認)。
- `begin_call` で各引数の `object_id` を「追跡中テーブル」へ登録。`end_call` で必ず除去(GC 後の `object_id` 再利用対策。テーブルは呼び出しスコープで明示的に掃除する方針とし、WeakRef は補助に留める)。
- TracePoint 側: `tp.self` の `object_id` が追跡中テーブルにあれば、`(メソッド名, 引数個数, ブロック有無)` を、その引数を所有する全活性コンテキストのプロトコルへ加算する。

### 4.4 帰属(attribution)— Error と Requirements で共通の構造

エフェクト/例外の発火時、活性コールスタック上の**全コンテキスト**に記録し、最深フレームのみ `direct: true`、それ以外は `inherited`(継承元メソッド名付き)とタグ付けする。

```ruby
def self.record_effect(kind, **detail)
  stack = call_stack          # Thread-local
  stack.each_with_index do |ctx, i|
    ctx.add_requirement(kind, detail, direct: i == stack.size - 1)
  end
end
```

これにより「メソッドAの引数規約・Requirements は callee B から流入した分を含む(推移的伝播)」が自然に成立し、かつ direct/inherited の区別により後段で B 変更時の差分解析が可能になる。

### 4.5 再入ガード(最重要の実装注意)

**トレーサ自身のコードがフックを発火させる無限再帰**が最初に踏む罠。記録処理は `Time.now` や Hash 操作を普通に行うため、Thread-local の `in_tracer` フラグで再入を遮断する:

```ruby
def self.record(...)
  return if Thread.current[:ethotrace_in_tracer]
  Thread.current[:ethotrace_in_tracer] = true
  # ... 記録処理 ...
ensure
  Thread.current[:ethotrace_in_tracer] = false
end
```

### 4.6 エフェクトスパン(レイヤリングと重複抑制)

Rails アダプタが `db.query` を記録する裏で pg のソケット書き込みを core の IO フックが二重記録する問題への対策。上位アダプタは `with_effect_span("db.query", ...)` で区間を宣言し、区間中に発火した下位エフェクトは**子として畳み込む or 抑制**する。OpenTelemetry のスパン階層と同型の設計を採用する。

### 4.7 stdlib アダプタ(core 内蔵)が張るフック

| エフェクト語彙 | フック先 | detail |
|---|---|---|
| `env.read` / `env.write` | `ENV.singleton_class` に prepend(`[]`, `fetch`, `[]=` 等) | key 名 |
| `io.read` / `io.write` | `File.open`, `IO.read/write` 等 | 正規化パス, mode |
| `time.read` | `Time.now`, `Process.clock_gettime` | — |
| `random.read` | `Random`, `SecureRandom` | — |
| `process.exec` | `Kernel#system`, バッククォート, `spawn` | コマンド(機微情報マスク検討) |
| `stdio.write` | `$stdout` / `$stderr` への書き込み | stream |
| `global.write` | `Kernel#trace_var`(対象グローバルの**代入のみ**) | 変数名 |

**既知の制約**: グローバル変数の**読み取り**は Ruby の仕組み上フック不可。「書き込みのみ観測」と仕様・出力に明記する。

---

## 5. アダプタAPI(プラグイン契約)

```ruby
module Ethotrace
  class Adapter
    # 計装フェーズ: チョークポイントへのフック登録
    def install(instrumenter); end
    def uninstall(instrumenter); end

    # ライフサイクル: セッション(=テストワーカー)単位
    def on_session_start(session); end
    def on_session_end(session); end
  end
end
```

`instrumenter` が提供する操作(最小セット):

- `record_effect(kind, write:, **detail)` — エフェクト記録(帰属は core が行う)
- `with_effect_span(kind, **detail) { ... }` — スパン宣言(下位エフェクトの畳み込み)
- `wrap_method(klass, name)` / `watch_targets(matcher)` — 計装対象の追加
- `on_load(const_name) { ... }` — 遅延ロードされるクラスへの計装予約(Rails アダプタが Zeitwerk と接続)

### Rails アダプタの実装方針(`ethotrace-rails`)

- `Railtie` で起動時に組み込み。
- DB は **`ActiveSupport::Notifications` の `sql.active_record` 購読**を第一選択とする(アダプタ prepend より安全・高情報量)。SQL からテーブル名と read/write を抽出して `db.query` として記録。
- HTTP は `Net::HTTP#request` フック(ホスト名を detail に)。
- **Zeitwerk の遅延ロード問題**: アプリのクラスは autoload されるため起動時に prepend できない。`Rails.application.config.to_prepare` または Zeitwerk の `on_load` コールバックで**ロード時計装**を行う。この解決自体が本 gem の主要な存在価値。
- Rails の `parallelize` / spring の fork に備え、セッションIDは PID + ワーカーIDで一意化。

---

## 6. データスキーマ(JSONL / gem 間の安定契約)

- 1行 = 1レコードの JSON Lines。**追記可能・後からマージ可能**であることが必須(並列テストワーカー対応)。
- 全レコードに `schema_version`(整数)を付与。スキーマ変更は version を上げ、マージCLIは混在を検出して警告する。
- ファイル配置の既定: `tmp/ethotrace/<session_id>.jsonl` → マージ後 `ethotrace/observations.json`(確定形式は実装時に決定)。

### 観測レコード例(`type: "method_observation"`)

```json
{
  "schema_version": 1,
  "type": "method_observation",
  "method": {"owner": "Order", "name": "total_price", "kind": "instance"},
  "site": {"path": "app/models/order.rb", "line": 12},
  "params": [
    {
      "position": 0, "name": "items",
      "protocol": [{"name": "each", "block": true}, {"name": "size"}],
      "classes_seen": ["Array"]
    }
  ],
  "return": {"classes_seen": ["Integer"]},
  "errors": [
    {"class": "KeyError", "origin": "inherited", "from": "Hash#fetch"}
  ],
  "requirements": [
    {"kind": "env.read", "write": false, "direct": true, "detail": {"key": "TAX_RATE"}},
    {"kind": "db.query", "write": false, "direct": false, "from": "Item#price",
     "detail": {"tables": ["items"]}}
  ],
  "samples": 17,
  "session": "rspec-w1-pid4242",
  "captured_at": "2026-06-11T12:00:00+09:00"
}
```

### マージ意味論

- 同一メソッドのレコードは**和集合**で統合(プロトコル・errors・requirements とも)。`samples` は加算。
- `classes_seen` は観測されたクラス名の集合(公称型情報は捨てず**補助情報**として保持。主役はあくまで protocol)。
- 将来の拡張: 呼び出しパターンごとのオーバーロード分割。v1 では和集合のみとし、生データに `samples` 単位の分布を残すかは未決定事項(§11)。

---

## 7. エフェクト語彙の規約

- 語彙は **開かれた名前空間**: ドット区切り文字列(`env.read`, `db.query`, `http.request`, `aws.s3.put` …)。core は語彙の意味を知らない。
- 必須属性: `write`(boolean)。読み取り系(ENV読み・SELECT・時刻取得)= Requirements 的、書き込み系(ファイル書込・INSERT・ENV変更)= Side Effects 的、という解釈は**表示・クエリ層で行う**。保存形式はフラットに記録 + 属性で区別(生データ主義)。
- アダプタ独自語彙は gem 名等で prefix することを推奨(衝突回避)。

---

## 8. 既知の制約・落とし穴(実装時チェックリスト)

1. **再入ガード**(§4.5)を最初に実装する。これがないと一切動かない。
2. `:c_call` の TracePoint は高コスト。既定では `:call` のみとし、`:c_call` はオプトイン設定にする。
3. `method_missing` / `send` / `public_send` 経由の呼び出し: TracePoint `:call` では `method_missing` 自体が見える。プロトコルとしてどう記録するかは v1 では「見えたまま記録」とする。
4. `object_id` の GC 後再利用 → 追跡テーブルは呼び出し終了時に必ず掃除(§4.3)。
5. frozen リテラル・シンボル等の**共有オブジェクト**: 複数コンテキストが同一 object_id を追跡し得る。帰属は「所有コンテキスト全部」に行う設計なので破綻はしないが、ノイズ(共有文字列への呼び出し混入)に注意。
6. グローバル変数の読み取りはフック不可(書き込みのみ、`trace_var`)。
7. Rails: Zeitwerk 遅延ロード(§5)。
8. 並列テスト: セッション分離 + マージ前提(§6)。fork 後のフック生存確認。
9. テストカバレッジ依存 = observed contract(§1)。出力に必ず明記。
10. スレッド/Fiber ごとのコンテキストスタック分離。Fiber スケジューラ(async gem 等)下での挙動は v1 ではベストエフォート。
11. ラッパーは挙動を一切変えない: 引数委譲・`frozen?`・`method(:x).source_location`・例外の `backtrace` 汚染最小化に注意。
12. 機微情報: ENV の key は記録するが **value は記録しない**。SQL はテーブル名抽出後の原文保存はオプション(既定OFF)。

---

## 9. 実装ロードマップ

各マイルストーンは「動くもの + テスト」で完結させる。TDD 推奨(本ツール自体がテスト実行を前提とするため、自分のテストで自分を観測する dogfooding が後半で可能になる)。

- **M0: スキャフォールド**
  - モノレポ or マルチ gem リポジトリ構成の決定(推奨: 単一リポジトリに `gems/ethotrace`, `gems/ethotrace-rspec`, … を置くモノレポ)。
  - `ethotrace` gem 骨格、Ruby >= 3.2 を対象、RSpec + RuboCop(standard でも可)整備。
  - データスキーマ v1 を `docs/schema.md` として確定。
- **M1: Success / Error チャネル**
  - prepend ラッパー、Tracker、CallContext スタック(Thread-local)、再入ガード。
  - 戻り値クラス記録、エスケープ例外記録(direct/inherited)。
  - JSONL ライター。単体 gem として手動 `Ethotrace.wrap(Klass, :meth)` で動く状態。
- **M2: Requirements チャネル + stdlib アダプタ**
  - アダプタAPI(§5)を先に定義し、ENV / Time / Random フックを**そのAPI経由で**実装(dogfooding)。
  - 帰属機構、エフェクトスパン。
  - 次に IO / process / stdio フック。
- **M3: 引数プロトコル観測**
  - TracePoint エンジン、追跡テーブル、`enable(target:)` による範囲限定。
  - `:c_call` オプトイン。プロトコルのマージ。
- **M4: テストフレームワーク接続 + マージ**
  - `ethotrace-rspec`(`around(:suite)` 相当でセッション管理)、マージ CLI(`ethotrace merge`)。
  - サンプル gem プロジェクトでの E2E。
- **M5: Rails アダプタ**
  - Railtie、Notifications 購読(`db.query`)、Zeitwerk ロード時計装、Net::HTTP フック。
  - サンプル Rails アプリ(リポジトリ内 `examples/rails-app`)で E2E。
- **M6: 消費者 gem**
  - `ethotrace-mcp`: 「このメソッドの引数0は何を要求するか」「R=∅(純粋)なメソッド一覧」「`time.read`/`random` を含む flaky 容疑メソッド一覧」等のクエリをツールとして公開。
  - `ethotrace-rbs`: protocol → RBS `interface` 投影(例外・Requirements は RBS に存在しないため欠落をコメントで明記)。

---

## 10. テスト戦略

- core の単体テスト: ラッパーの透過性(引数委譲・例外再送出・戻り値同一性)、再入ガード、object_id 掃除、スレッド分離。
- フィクスチャとして「既知の規約を持つ小さなクラス群」を用意し、観測結果 JSONL をゴールデンファイル比較。
- 性能ベンチ: TracePoint なし / `:call` のみ / `:c_call` 込み の3構成でオーバーヘッドを継続計測(`benchmark-ips`)。目標値は計測後に設定。

---

## 11. 未決定事項(実装中に判断してよい / 要相談)

1. プロジェクト名・gem 名の確定(rubygems.org での衝突確認)。
2. プロトコルの粒度: メソッド名のみ vs 引数個数・ブロック有無まで(v1 は後者を推奨)。
3. オーバーロード分割(呼び出しパターン別)を生データに残すか、和集合のみか。
4. ブロック引数のプロトコル(yield される値の観測)— v2 候補。
5. 戻り値オブジェクトが**呼び出し元でどう使われるか**(Success 側のプロトコル)の観測 — v2 候補。追跡テーブルを return 後も呼び出し元コンテキスト存続中だけ維持すれば実現可能。
6. SQL 原文の保存ポリシー(既定OFFの方針のみ決定済み)。
7. マージ後の正規化ストア形式(JSON 単一ファイル / SQLite)。MCP の応答性能要件次第。

---

## 12. 参考(先行研究・類似ツール)

- **Rubydust** — "Dynamic Inference of Static Types for Ruby" (POPL 2011)。引数をラッパーで包んで呼び出しを記録し型制約を収集。本システムに最も近い先行研究だが、最終的に公称型へ解決する点が異なる。
- `rbs prototype runtime`, `rbs-trace` — 実行時観測から RBS 生成。型名へ落とすため構造情報と例外・Requirements が欠落。
- RBS の `interface`(構造的インターフェース構文)— `ethotrace-rbs` の投影先。
- Sorbet (`sorbet-runtime` の `T.sig`), TypeProf — 公称型・静的解析系の比較対象。
- OpenTelemetry のスパン階層 — エフェクトスパン設計の参照モデル。
- Effect-TS の `Effect<Success, Error, Requirements>` — 三チャネルモデルの着想元。

---

## 付録: Claude Code への実装指示メモ

- まず M0〜M1 を完了させ、各マイルストーン末でテストグリーンを確認してからコミットすること。
- core に Rails / RSpec への依存を**絶対に**持ち込まない(Gemfile レベルで分離)。
- stdlib フックも必ず公開アダプタAPI経由で実装する(§3 dogfooding 原則)。違反は設計バグとして扱う。
- 再入ガード(§4.5)とラッパー透過性のテストを最優先で書く。
- データスキーマ変更時は `schema_version` を上げ、`docs/schema.md` を同時更新する。
