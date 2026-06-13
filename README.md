# Ethotrace

**Ethotrace** は Ruby 向けの動的型検査・シグネチャ解析システム。公称型(型名)ではなく、
テスト実行中のメソッド呼び出しを観測して「振る舞い(プロトコル)」「伝播例外」
「実行環境要件(Requirements)」を三チャネルで記録する。

設計思想は Effect-TS の `Effect<Success, Error, Requirements>` モデルに着想を得ている。
詳細な設計は [`docs/ethotrace-design-handoff-v2.md`](docs/ethotrace-design-handoff-v2.md)、
gem 間の安定契約である JSONL スキーマは [`docs/schema.md`](docs/schema.md) を参照。

> 観測結果は **observed contract(観測された下限)** であり、テストカバレッジに依存する。
> 未実行パスの規約は含まれない。これは欠陥ではなく仕様である。

## モノレポ構成

単一リポジトリに複数 gem を置くモノレポ構成(段階的に追加予定):

| gem | 役割 |
|---|---|
| `gems/ethotrace` | core: 観測エンジン + stdlib アダプタ + JSONL ライター + マージ CLI |
| `gems/ethotrace-rspec` | RSpec ライフサイクル接続 |
| `gems/ethotrace-minitest` | Minitest 版(予定) |
| `gems/ethotrace-rails` | Railtie / ActiveSupport::Notifications / Zeitwerk 連携(予定) |
| `gems/ethotrace-mcp` | MCP サーバ(予定) |
| `gems/ethotrace-rbs` | RBS interface への投影(予定) |

## 実装状況

| マイルストーン | 内容 | 状態 |
|---|---|---|
| M0 | スキャフォールド + スキーマ v1 確定 | ✅ |
| M1 | prepend ラッパー + Tracker + CallContext + 再入ガード + JSONL ライター(Success / Error チャネル) | ✅ |
| M2 | アダプタ API + stdlib アダプタ(ENV/Time/Random/IO/Process)+ Requirements 帰属 + エフェクトスパン | ✅ |
| M3 | TracePoint エンジン + 引数プロトコル観測 | ✅ |
| M4 | `ethotrace-rspec`(スイートライフサイクル接続)+ マージ CLI(`ethotrace merge`) | ✅ |
| M5 | 自己適用(self-hosting)+ 隔離戦略(`NullIsolation` / `BoxIsolation`)+ collector/probe 分離 | ✅ |
| M6 | `ethotrace-mcp`(自己観測データを参照する MCP サーバ) | 予定 |
| M7 | `ethotrace-rails`(Railtie / Notifications / Zeitwerk) | 予定 |
| M8 | `ethotrace-rbs`(protocol → RBS `interface` 投影) | 予定 |

> ロードマップは設計資料 v2 で改定済み: **MCP を Rails より先に作る**。M5 で自己適用を達成し、
> M6 の MCP 経由で以降の開発を自己観測データで支援するブートストラップループに入る(§9)。

core の使い方は [`gems/ethotrace/README.md`](gems/ethotrace/README.md) を参照。

## 使い方(RSpec)

`ethotrace-rspec` をテストに組み込むと、スイート開始/終了に観測セッションが接続され、
テストワーカーごとに `tmp/ethotrace/<session>.jsonl` が書き出される。`spec_helper.rb` で:

```ruby
require "ethotrace/rspec"

Ethotrace::RSpec.setup do |config|
  config.observe Order                  # Order 自身のインスタンスメソッド全部
  config.observe Tax, methods: %i[rate] # 一部メソッドだけを指定
  # config.options[:trace_c_call] = true  # C メソッドもプロトコルに含める(高コスト)
end
```

並列テスト(parallel_tests)ではワーカーごとに `TEST_ENV_NUMBER` と PID から
セッション ID を導出し(例: `rspec-w2-pid4242`)、別ファイルへ書き分ける。

## マージ(`ethotrace merge`)

並列ワーカーが吐いた複数の JSONL を 1 つへ統合する。`(owner, name, kind)` をキーに、
プロトコル・例外・Requirements を和集合、`samples` を加算する(→ [`docs/schema.md`](docs/schema.md) §7)。

```bash
bundle exec ethotrace merge tmp/ethotrace/*.jsonl -o ethotrace/observations.jsonl
```

出力は `method_observation` 形を 1 行 1 レコードで保つため**再マージ可能**。
`-o` を省略すると標準出力へ純粋な JSONL を流す(進捗・サマリは標準エラーへ)。
マージ結果は `ethotrace view` でそのまま閲覧できる。

## 自己適用(self-hosting)と隔離戦略

Ethotrace は **観測の設置先**を差し替え可能な隔離戦略(`Ethotrace::Isolation`)として持つ。
probe(prepend フック)を「どの空間で」走らせるかだけを戦略が決め、collector(記録・帰属・
JSONL)と TracePoint は常に root 側に置く。

| 戦略 | 条件 | 用途 |
|---|---|---|
| `Isolation::Null` | 既定 | 通常の解析(probe = collector 同一空間)|
| `Isolation::Box` | Ruby >= 4.0 + `RUBY_BOX=1` | 自己適用・モンキーパッチの激しい対象 |

`Isolation::Box` は子 [`Ruby::Box`](https://docs.ruby-lang.org/en/4.0/Ruby/Box.html)(Ruby 4.0
experimental)に Ethotrace を新規ロードし、観測対象を root と別実体に隔離する。これにより
「計装機構そのものが計装対象になる」自己言及汚染が構造的に解ける。観測イベントは box 内 probe
から root の Collector へ橋渡しされる。加えて記録の活性パスは名前ベースの deny-list
(`Wrapper::SELF_DENY_LIST`)で二重に保護する。

```bash
# 自己適用デモ: Ethotrace で Ethotrace 自身のメソッドを観測する(main box から起動)
RUBY_BOX=1 ruby gems/ethotrace/script/self_hosting.rb
```

Ruby::Box の検証結果(実体分離・越境観測・系譜依存など E1〜E6)は
[`docs/box-semantics.md`](docs/box-semantics.md) に、設計の詳細は設計資料 §4.8 に記す。
Ruby::Box は experimental かつ main box からの起動を要するため、自己適用の検証は上記の
スタンドアロンハーネス(素の `RUBY_BOX=1 ruby`)で行う(`RUBY_BOX=1` 下では bundler/rspec が
stdlib autoload の問題で動かない)。**Rails アダプタ + BoxIsolation の併用は当面サポート外**。

## 開発

Ruby >= 3.2 が必要。

```bash
bundle install          # 依存解決(ルートの Gemfile が全 gem を束ねる)
bundle exec rake        # 全 gem の spec + RuboCop
bundle exec rake spec   # テストのみ
bundle exec rake rubocop
```

## ライセンス

MIT
