# Ethotrace

**Ethotrace** は Ruby 向けの動的型検査・シグネチャ解析システム。公称型(型名)ではなく、
テスト実行中のメソッド呼び出しを観測して「振る舞い(プロトコル)」「伝播例外」
「実行環境要件(Requirements)」を三チャネルで記録する。

設計思想は Effect-TS の `Effect<Success, Error, Requirements>` モデルに着想を得ている。
詳細な設計は [`ethotrace-design-handoff.md`](ethotrace-design-handoff.md)、
gem 間の安定契約である JSONL スキーマは [`docs/schema.md`](docs/schema.md) を参照。

> 観測結果は **observed contract(観測された下限)** であり、テストカバレッジに依存する。
> 未実行パスの規約は含まれない。これは欠陥ではなく仕様である。

## モノレポ構成

単一リポジトリに複数 gem を置くモノレポ構成(段階的に追加予定):

| gem | 役割 |
|---|---|
| `gems/ethotrace` | core: 観測エンジン + stdlib アダプタ + JSONL ライター + マージ CLI |
| `gems/ethotrace-rspec` | RSpec ライフサイクル接続(予定) |
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
| M4 | `ethotrace-rspec` + マージ CLI | 予定 |
| M5 | `ethotrace-rails`(Railtie / Notifications / Zeitwerk) | 予定 |
| M6 | `ethotrace-mcp` + `ethotrace-rbs` | 予定 |

core の使い方は [`gems/ethotrace/README.md`](gems/ethotrace/README.md) を参照。

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
