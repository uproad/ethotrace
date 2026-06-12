# Ethotrace (core)

**Ethotrace** は Ruby 向けの動的型検査・シグネチャ解析システム。公称型(型名)ではなく、
テスト実行中のメソッド呼び出しを観測して「振る舞い(プロトコル)」「伝播例外」
「実行環境要件(Requirements)」を三チャネルで記録する。

この gem は **core** — 観測の物理学を担う層である。`Module#prepend` ラッパーによる
Success / Error の捕捉、コールスタック管理、例外の帰属、三チャネルのデータモデル、
JSON Lines シリアライズを提供する。**Rails にも RSpec にも依存しない。**
計装対象の選択やテストライフサイクル接続といった意味論はアダプタ gem が担う。

> 観測結果は **observed contract(観測された下限)** であり、テストカバレッジに依存する。
> 未実行パスの規約は含まれない。これは欠陥ではなく仕様である。

設計の詳細は [`ethotrace-design-handoff.md`](../../ethotrace-design-handoff.md)、
gem 間の安定契約である JSONL スキーマは [`docs/schema.md`](../../docs/schema.md) を参照。

## 実装状況

| マイルストーン | 内容 | 状態 |
|---|---|---|
| M0 | スキャフォールド + スキーマ v1 確定 | ✅ |
| M1 | prepend ラッパー + Tracker + CallContext + 再入ガード + JSONL ライター | ✅ |
| M2 | アダプタ API + stdlib アダプタ(ENV/Time/Random/IO/Process)+ Requirements 帰属 + エフェクトスパン | ✅ |
| M3 | TracePoint エンジン + 引数プロトコル観測 | ✅ |
| M4〜 | RSpec / マージ CLI / Rails / MCP / RBS | 予定 |

現時点(M3)では三チャネルのうち **Success(戻り値クラス)**・**Error(エスケープ例外と
direct/inherited 帰属)**・**Requirements(外部接触: `env.read`/`env.write`/`time.read`/
`random.read`/`io.read`/`io.write`/`process.exec`)** に加え、**引数プロトコル(`params`)** を
観測できる。`Session` の配下では `TracePoint` で各実引数に対して実際に呼ばれたメソッド集合
(`(name, arity, block)` 粒度)を記録し、`classes_seen`(観測された実クラス)も併記する。
C 実装メソッド(`Array#each` など)は高コストのため既定では観測されず、`trace_c_call: true`
オプトイン時のみ `params` に現れる。

## インストール

未リリースのため、git 参照で利用する(モノレポのルートから `bundle install` すれば解決される):

```ruby
gem "ethotrace", git: "https://github.com/uproad/ethotrace", glob: "gems/ethotrace/*.gemspec"
```

## 使い方

計装対象のメソッドを `Wrapper.wrap` で包み、完了した観測の購読者として `JSONLWriter` を
登録する。被計装メソッドを呼ぶたびに、戻り値・エスケープ例外が JSON Lines として書き出される。

```ruby
require "ethotrace"

class Order
  def total_price(items)
    items.sum { |item| item.fetch(:price) }
  end
end

# 観測結果の出力先(ここでは標準出力。ファイルなら JSONLWriter.open を使う)。
writer = Ethotrace::JSONLWriter.new($stdout, session: "demo-pid#{Process.pid}")

# 完了した観測の購読者として登録し、対象メソッドを計装する。
Ethotrace::Wrapper.subscribe(writer)
Ethotrace::Wrapper.wrap(Order, :total_price)

Order.new.total_price([{ price: 300 }, { price: 700 }])  # => 1000(透過。挙動は変わらない)

begin
  Order.new.total_price([{ amount: 100 }])  # KeyError がエスケープ
rescue KeyError
  # 例外はそのまま再送出される。観測は Error チャネルへ記録される。
end
```

上のコードは次のような JSONL を出力する(`session` レコード 1 行 +
呼び出しごとの `method_observation` レコード):

```json
{"schema_version":1,"type":"session","session":"demo-pid1234", ...}
{"schema_version":1,"type":"method_observation","method":{"owner":"Order","name":"total_price","kind":"instance"},"return":{"classes_seen":["Integer"]},"errors":[], ...}
{"schema_version":1,"type":"method_observation","method":{"owner":"Order","name":"total_price","kind":"instance"},"return":{"classes_seen":[]},"errors":[{"class":"KeyError","origin":"direct","from":null}], ...}
```

ファイルへ書き出す場合は `JSONLWriter.open` を使う(ブロック終了時に自動 close):

```ruby
Ethotrace::JSONLWriter.open("tmp/ethotrace/#{session_id}.jsonl", session: session_id) do |writer|
  Ethotrace::Wrapper.subscribe(writer)
  # ... テストを実行 ...
end
```

レコードの完全なフィールド定義は [`docs/schema.md`](../../docs/schema.md)(schema_version 1)を参照。

### Requirements も観測する(アダプタ込みのセッション)

`Ethotrace::Session` で囲むと、core 内蔵の **stdlib アダプタ**(ENV/Time/Random/IO/Process)が
有効になり、被計装メソッドの実行中に触れた外部世界(Requirements チャネル)も記録される。
session レコードには有効なアダプタ名と観測オプションが載る。

```ruby
session = Ethotrace::Session.start($stdout, id: "demo-pid#{Process.pid}")

class Tax
  def rate = Integer(ENV.fetch("TAX_RATE"))  # env.read が記録される
end
Ethotrace::Wrapper.wrap(Tax, :rate)
Tax.new.rate

session.finish  # アダプタ終了通知・購読解除・出力先 close
```

`rate` の観測には `requirements: [{ "kind": "env.read", "detail": { "key": "TAX_RATE" } }]`
が含まれる(**ENV の値は記録しない** — key のみ)。アダプタが `with_effect_span("db.query") { ... }`
で区間を宣言すると、区間中の下位エフェクト(例: ソケットへの `io.write`)は畳み込まれて
重複記録されない。

### 引数プロトコルも観測する(M3)

`Session` 配下では引数プロトコル(`params`)も自動で観測される。被計装メソッドの実行中に
`TracePoint` が各実引数オブジェクトへの呼び出しを捕捉し、「この引数に対して実際に呼ばれた
メソッド集合」を記録する。公称型ではなく**振る舞い(プロトコル)**で引数を特徴づける。

```ruby
session = Ethotrace::Session.start($stdout, id: "demo-pid#{Process.pid}")

class Greeter
  def greet(user) = "hi, #{user.name.upcase}"  # user に name が呼ばれる
end
Ethotrace::Wrapper.wrap(Greeter, :greet)
Greeter.new.greet(some_user)

session.finish
```

`greet` の観測には、第 0 引数 `user` のプロトコルが記録される:

```json
{
  "params": [
    { "position": 0, "name": "user",
      "protocol": [{ "name": "name", "arity": 0, "block": false }],
      "classes_seen": ["User"] }
  ]
}
```

> **値共有 immediate**(`Integer` / `Symbol` / `Float` / `true` / `false` / `nil`)は object_id が
> 値で共有され誤帰属するため、`classes_seen` は記録するがプロトコル追跡の対象外(v1 の割り切り)。
> **C 実装メソッド**(`String#upcase` など)は既定では `protocol` に現れず、
> `Session.start(io, options: { trace_c_call: true })` でオプトインしたときのみ観測される(高コストのため)。

## CLI: 観測結果をターミナルで見る

書き出した JSONL は `ethotrace view` でさっと確認できる(開発者がローカルで見る用途)。
複数ファイルは schema §7 のマージ意味論(`(owner, name, kind)` で和集合・`samples` 加算)で
表示用に統合される。

```bash
# サマリ: メソッドごとに 1 行(戻り値・引数プロトコル種類数・エラー種類数・samples)
bundle exec ethotrace view tmp/ethotrace/*.jsonl
```

```text
2 methods · 1 sessions · 6 samples

[1] Order.create       return: Symbol   args: 0  errors: 0  samples: 3
[2] Order#total_price  return: Integer  args: 0  errors: 1  samples: 3
```

詳細(全情報)は index か メソッド名で開く。三チャネル + 引数プロトコルのセクションは
常に表示する(観測が無いチャネルは枠だけ出す)。

```bash
bundle exec ethotrace view tmp/ethotrace/*.jsonl -i 2   # --index 2
bundle exec ethotrace view tmp/ethotrace/*.jsonl -m "Order#total_price"  # --method
```

```text
Order#total_price  (instance)
  site     : app/models/order.rb:12
  samples  : 3
  sessions : rspec-w1-pid42

  return (Success):
    Integer

  args (protocol):
    (none observed)

  errors (Error):
    KeyError  [direct]

  requirements:
    (none observed)
```

色は TTY 出力時のみ付く(`NO_COLOR` または `--no-color` で無効化)。

## CLI: 観測結果をマージする

並列テストワーカーが吐いた複数の JSONL を `ethotrace merge` で 1 つへ統合する。`view` の
表示用統合と異なり、こちらは errors の origin/from・requirements の detail・プロトコルの
arity/block まで**データを一切捨てず**、`observations.jsonl` として書き出す。

```bash
# 統合して観測ストアへ(1 メソッド = 1 行の JSONL を維持 → 再マージ可能)
bundle exec ethotrace merge tmp/ethotrace/*.jsonl -o ethotrace/observations.jsonl
```

`-o` を省略すると標準出力へ純粋な JSONL を流す(進捗・サマリは標準エラーへ出すのでパイプできる)。
マージ後レコードはセッション ID を `sessions`(配列)へ正規化し、入力と同じ `method_observation`
形を保つため、`observations.jsonl` 同士や新しい生ログと**再マージできる**(→ schema §7.1)。

## 構成要素(core)

| 要素 | 役割 |
|---|---|
| `ReentryGuard` | トレーサ自身のコードがフックを再発火させる無限再帰を防ぐ Thread/Fiber-local フラグ。 |
| `CallContext` | 1 回の呼び出しに対応する観測アキュムレータ。Success / Error / Requirements / 引数プロトコルを蓄積し `#to_observation` を生成。 |
| `Tracker` | Thread/Fiber-local のコールスタック。`begin_call` / `end_call` と例外の direct/inherited 帰属。 |
| `ArgumentTable` | 実引数の object_id を「どの context の第何引数か」で追跡する Thread/Fiber-local テーブル。`end_call` で必ず掃除する。 |
| `ProtocolTracer` | `TracePoint`(`:call`、`:c_call` はオプトイン)で引数オブジェクトへの呼び出しを捕捉し、プロトコルへ加算する観測エンジン。 |
| `Instrumentation` | 横取りモジュールの生成・prepend・記述子算出(可視性も保存)という計装の物理機構。 |
| `Wrapper` | 計装レジストリ(二重 wrap 禁止)・観測ランタイム・購読者の継ぎ目を束ねるオーケストレーション。 |
| `JSONLWriter` | `session` / `method_observation` レコードを JSON Lines として追記出力するシンク。 |

### 透過性の保証(挙動を一切変えない)

prepend ラッパーは引数(`*args, **kwargs, &block`)・キーワード・ブロックをそのまま委譲し、
戻り値の同一性を保ち、エスケープ例外は必ず再送出する。元メソッドの可視性(private/protected)も
保存する。観測の記録処理は再入ガード下でのみ行い、`super` はガードの外で呼ぶため、ネストした
被観測呼び出しを潰さない。記録中に内部エラーが起きてもユーザーへは伝播させず、観測のみ無効化する。

## 開発

```bash
# モノレポのルートから実行する
bundle exec rake          # 全 gem の spec + RuboCop
bundle exec rake spec     # テストのみ
bundle exec rake rubocop
```

## ライセンス

MIT License の下で公開されるオープンソースである。
