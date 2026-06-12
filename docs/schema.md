# Ethotrace 観測データスキーマ (schema_version 1)

> このスキーマは **gem 間の安定契約**である。観測プロセス(core + アダプタ)と
> 消費プロセス(`ethotrace-mcp` / `ethotrace-rbs` / マージ CLI)は Ruby API ではなく
> この JSONL スキーマを介して結合する。原理的には別言語実装の消費者も書ける構造とする。
>
> **スキーマを変更する際は `schema_version` を上げ、本ドキュメントを同時に更新すること。**
> マージ CLI は異なる `schema_version` の混在を検出して警告する。

## 0. 設計上の前提

- 観測結果は **observed contract(観測された下限)** である。テストカバレッジに依存し、
  未実行パスの規約は含まれない。これは欠陥ではなく仕様であり、出力にも明示する。
- 保存形式は**生データ主義**: 解釈(Requirements と Side Effects の区別、インターフェース命名など)は
  上位レイヤー(表示・クエリ層)で行う。core は意味を解釈せず、属性を平坦に記録する。

## 1. 物理フォーマット

- **JSON Lines**: 1 行 = 1 レコードの JSON。改行区切り。
- **追記可能・マージ可能**であること(並列テストワーカー対応)が必須要件。
- 文字エンコーディングは UTF-8。
- 既定のファイル配置:
  - セッション単位の生ログ: `tmp/ethotrace/<session_id>.jsonl`
  - マージ後の確定ストア: `ethotrace/observations.jsonl`(**JSON Lines を維持**。1 メソッド =
    1 行で追記・再マージ可能。§7 参照)

## 2. 共通フィールド

すべてのレコードは以下を持つ。

| フィールド | 型 | 説明 |
|---|---|---|
| `schema_version` | integer | スキーマバージョン。v1 では `1` 固定。 |
| `type` | string | レコード種別。`"method_observation"` / `"session"`。 |

## 3. レコード種別: `session`

1 回のテスト実行(ワーカー)単位のメタ情報。セッション開始時に 1 行出力する。

```json
{
  "schema_version": 1,
  "type": "session",
  "session": "rspec-w1-pid4242",
  "started_at": "2026-06-11T12:00:00+09:00",
  "ruby_version": "3.4.1",
  "ethotrace_version": "0.0.1",
  "adapters": ["stdlib", "rspec-targets"],
  "options": { "trace_c_call": false, "record_sql_source": false }
}
```

| フィールド | 型 | 説明 |
|---|---|---|
| `session` | string | セッション識別子。並列実行では `<runner>-w<worker>-pid<pid>` 等で一意化する。 |
| `started_at` | string (RFC 3339) | セッション開始時刻。 |
| `ruby_version` | string | 観測時の Ruby バージョン。 |
| `ethotrace_version` | string | 観測に用いた core のバージョン。 |
| `adapters` | array<string> | 有効だったアダプタ名の一覧。 |
| `options` | object | 観測オプション(`:c_call` 計装の有無、SQL 原文記録の有無など)。 |

## 4. レコード種別: `method_observation`

観測の主役。1 メソッドに対する三チャネル(Success / Error / Requirements)+ 引数プロトコルの観測結果。

```json
{
  "schema_version": 1,
  "type": "method_observation",
  "method": { "owner": "Order", "name": "total_price", "kind": "instance" },
  "site": { "path": "app/models/order.rb", "line": 12 },
  "params": [
    {
      "position": 0,
      "name": "items",
      "protocol": [
        { "name": "each", "arity": 0, "block": true },
        { "name": "size", "arity": 0, "block": false }
      ],
      "classes_seen": ["Array"]
    }
  ],
  "return": { "classes_seen": ["Integer"] },
  "errors": [
    { "class": "KeyError", "origin": "inherited", "from": "Hash#fetch" }
  ],
  "requirements": [
    { "kind": "env.read", "write": false, "direct": true, "detail": { "key": "TAX_RATE" } },
    { "kind": "db.query", "write": false, "direct": false, "from": "Item#price",
      "detail": { "tables": ["items"] } }
  ],
  "samples": 17,
  "session": "rspec-w1-pid4242",
  "captured_at": "2026-06-11T12:00:00+09:00"
}
```

### 4.1 `method`

| フィールド | 型 | 説明 |
|---|---|---|
| `owner` | string | メソッドを定義するクラス/モジュールの完全修飾名。 |
| `name` | string | メソッド名。 |
| `kind` | string | `"instance"` / `"singleton"`。 |

### 4.2 `site`

定義位置(`Method#source_location`)。観測不能な場合は `null`。

| フィールド | 型 | 説明 |
|---|---|---|
| `path` | string | ソースパス(リポジトリ相対に正規化)。 |
| `line` | integer | 定義行。 |

### 4.3 `params[]` — 引数プロトコル(Requirements ではなく**構造**の主役)

各仮引数に対し、実際に呼ばれたメソッド集合(プロトコル)を記録する。

| フィールド | 型 | 説明 |
|---|---|---|
| `position` | integer | 引数位置(0 起点)。 |
| `name` | string \| null | 仮引数名(取得可能な場合)。 |
| `protocol` | array<ProtocolEntry> | その引数オブジェクトに対して観測されたメソッド呼び出しの集合。 |
| `classes_seen` | array<string> | 観測された実引数のクラス名集合。**補助情報**であり主役ではない。 |

**ProtocolEntry**:

| フィールド | 型 | 説明 |
|---|---|---|
| `name` | string | 呼ばれたメソッド名。 |
| `arity` | integer | 渡された実引数の個数(v1 の粒度)。 |
| `block` | boolean | ブロックが渡されたか。 |

> v1 のプロトコル粒度は `(name, arity, block)`。`method_missing` / `send` 経由は
> 「見えたまま記録」する(`method_missing` 自体がプロトコルに現れうる)。

### 4.4 `return` — Success チャネル

| フィールド | 型 | 説明 |
|---|---|---|
| `classes_seen` | array<string> | 戻り値として観測されたクラス名集合。 |

> 戻り値オブジェクトに対する呼び出し元でのプロトコル観測は v2 候補(本スキーマでは未収録)。

### 4.5 `errors[]` — Error チャネル(エスケープ例外のみ)

メソッドの外へ**伝播(エスケープ)した**例外のみを記録する。内部で rescue された例外は含めない。

| フィールド | 型 | 説明 |
|---|---|---|
| `class` | string | 例外クラスの完全修飾名。 |
| `origin` | string | `"direct"`(当該メソッド自身で発生)/ `"inherited"`(callee から伝播)。 |
| `from` | string \| null | `inherited` の場合の伝播元メソッド(`Owner#name` 形式)。 |

### 4.6 `requirements[]` — Requirements チャネル(外部世界への接触)

| フィールド | 型 | 説明 |
|---|---|---|
| `kind` | string | エフェクト語彙(§5)。ドット区切りの開かれた名前空間。 |
| `write` | boolean | **必須**。書き込み系(副作用的)か読み取り系(要件的)か。 |
| `direct` | boolean | 当該メソッド自身での発火(`true`)か、callee からの継承(`false`)か。 |
| `from` | string \| null | `direct: false` の場合の継承元メソッド(`Owner#name` 形式)。 |
| `detail` | object | エフェクト固有の詳細(§5)。**機微情報は記録しない**(§6)。 |

## 5. エフェクト語彙の規約

- 語彙は**開かれた名前空間**: ドット区切り文字列(`env.read`, `db.query`, `http.request`, `aws.s3.put` …)。
  core は語彙の意味を知らない。
- 必須属性は `write`(boolean)。「読み取り = Requirements 的 / 書き込み = Side Effects 的」という解釈は
  表示・クエリ層で行う。保存はフラット。
- アダプタ独自語彙は gem 名等で prefix することを推奨(衝突回避)。

### core 内蔵 stdlib アダプタが張る語彙(v1)

| 語彙 | `write` | `detail` |
|---|---|---|
| `env.read` / `env.write` | false / true | `{ "key": "<NAME>" }`(value は記録しない) |
| `io.read` / `io.write` | false / true | `{ "path": "<正規化パス>", "mode": "<mode>" }` |
| `time.read` | false | `{}` |
| `random.read` | false | `{}` |
| `process.exec` | true | `{ "command": "<マスク済み>" }` |
| `stdio.write` | true | `{ "stream": "stdout" \| "stderr" }` |
| `global.write` | true | `{ "name": "$<var>" }`(**書き込みのみ観測可**。読み取りはフック不可) |

## 6. 機微情報のポリシー

- **ENV の value は記録しない**(key のみ)。
- **SQL 原文の保存は既定 OFF**。テーブル名抽出後のメタ情報のみを記録する。原文保存はオプトイン。
- `process.exec` のコマンド文字列はマスクを検討する。

## 7. マージ意味論

複数セッションの `method_observation` レコードは `(method.owner, method.name, method.kind)` をキーに統合する。
`ethotrace merge <files...> -o ethotrace/observations.jsonl` がこの統合を行う。

- `params[].protocol` / `errors` / `requirements` / `classes_seen` は**和集合**で統合する。
- `samples` は**加算**する。
- `site` は最初に観測された非 null を採る。
- 異なる `schema_version` の混在はマージ CLI が検出して警告する。
- v1 では和集合のみ。呼び出しパターン別のオーバーロード分割は将来拡張(§9)。

### 7.1 マージ後レコードの形

マージ結果も `type: "method_observation"` 形を保つ。ただしセッション文脈の差は次のとおり:

| フィールド | 生ログ(単一観測) | マージ後 |
|---|---|---|
| `session` | string(単一セッション ID) | — (置き換わる) |
| `sessions` | — | array<string>(寄与した全セッション ID。ソート済み) |
| `captured_at` | string(観測時刻) | — (落とす) |

マージ後レコードは入力と同じ `method_observation` 形を保つため、**再びマージ可能**である
(`observations.jsonl` 同士、あるいは新しい生ログとの再マージができる)。マージ実装は単一観測の
`session`(string)と既マージの `sessions`(array)の双方を入力として受け付ける。

```json
{
  "schema_version": 1,
  "type": "method_observation",
  "method": { "owner": "Order", "name": "total_price", "kind": "instance" },
  "site": { "path": "app/models/order.rb", "line": 12 },
  "params": [ /* … 和集合 … */ ],
  "return": { "classes_seen": ["Integer", "NilClass"] },
  "errors": [ /* … 和集合 … */ ],
  "requirements": [ /* … 和集合 … */ ],
  "samples": 42,
  "sessions": ["rspec-w1-pid4242", "rspec-w2-pid4243"]
}
```

## 8. 既知の制約(出力に明示すること)

1. observed contract: テストカバレッジ依存。未実行パスは含まれない。
2. グローバル変数の**読み取り**はフック不可(書き込みのみ観測)。
3. `:c_call` 計装は既定 OFF(高コスト)。オプトイン時のみ C メソッドがプロトコルに現れる。
4. frozen/共有オブジェクトへの呼び出しはノイズとして混入しうる。

## 9. 未決定事項(v1 では保留)

- オーバーロード分割(呼び出しパターン別)を生データに残すか、和集合のみか。
- マージ後の高速クエリ用ストア形式(SQLite 等)。確定形式は JSONL(`observations.jsonl`)だが、
  MCP の応答性能要件次第で派生インデックスを別途持つ可能性がある。
- ブロック引数(yield 値)のプロトコル観測 — v2 候補。
- 戻り値オブジェクトの呼び出し元プロトコル観測 — v2 候補。
