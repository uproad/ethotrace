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
| M2 | アダプタ API + stdlib アダプタ(ENV/Time/Random/IO)+ 帰属 + エフェクトスパン | 予定 |
| M3 | TracePoint エンジン + 引数プロトコル観測 | 予定 |
| M4〜 | RSpec / マージ CLI / Rails / MCP / RBS | 予定 |

現時点(M1)では **Success(戻り値クラス)** と **Error(エスケープ例外と direct/inherited 帰属)**
の二チャネルを観測できる。引数プロトコル(`params`)と Requirements は後続マイルストーンで実装する
(出力スキーマ上は空配列としてプレースホルダが入る)。

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
常に表示し、M1 で未観測の `params` / `requirements` も枠だけ出す(最終形を見据えた表示)。

```bash
bundle exec ethotrace view tmp/ethotrace/*.jsonl --index 2
bundle exec ethotrace view tmp/ethotrace/*.jsonl --method "Order#total_price"
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

## 構成要素(core)

| 要素 | 役割 |
|---|---|
| `ReentryGuard` | トレーサ自身のコードがフックを再発火させる無限再帰を防ぐ Thread/Fiber-local フラグ。 |
| `CallContext` | 1 回の呼び出しに対応する観測アキュムレータ。Success / Error を蓄積し `#to_observation` を生成。 |
| `Tracker` | Thread/Fiber-local のコールスタック。`begin_call` / `end_call` と例外の direct/inherited 帰属。 |
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
