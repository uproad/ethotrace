# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## プロジェクト概要

**Ethotrace** は Ruby 向け動的型検査・シグネチャ解析システム。公称型(型名)ではなく、テスト実行中のメソッド呼び出しを監視して「振る舞い(プロトコル)」「伝播例外」「実行環境要件(Requirements)」を三チャネルで記録する。

設計思想: Effect-TS の `Effect<Success, Error, Requirements>` モデルに着想を得た三チャネル観測。詳細は `ethotrace-design-handoff.md` を参照。

## Gem 構成(モノレポ)

単一リポジトリに複数 gem を置くモノレポ構成(予定):

```
gems/ethotrace          # core: 観測エンジン + stdlib アダプタ + JSONL ライター + マージ CLI
gems/ethotrace-rspec    # RSpec ライフサイクル接続
gems/ethotrace-minitest # Minitest 版
gems/ethotrace-rails    # Railtie / ActiveSupport::Notifications / Zeitwerk 連携
gems/ethotrace-mcp      # MCP サーバ(観測プロセスと完全分離)
gems/ethotrace-rbs      # RBS interface への投影
```

## コマンド(整備後)

```bash
# テスト実行
bundle exec rspec                          # 全テスト
bundle exec rspec spec/path/to/spec.rb     # 単一ファイル
bundle exec rspec spec/path/to/spec.rb:42  # 行番号指定

# Lint
bundle exec rubocop
bundle exec rubocop --autocorrect

# ベンチマーク
bundle exec ruby benchmarks/overhead.rb   # TracePoint なし / :call / :c_call の3構成

# 観測データのマージ
bundle exec ethotrace merge tmp/ethotrace/*.jsonl -o ethotrace/observations.json
```

## アーキテクチャの核心

### 観測機構(ハイブリッド)

| チャネル | 機構 |
|---|---|
| Success(戻り値) / Error(エスケープ例外) | `Module#prepend` ラッパー |
| 引数プロトコル(呼ばれたメソッド集合) | `TracePoint` (`:call`、`:c_call` はオプトイン) |
| Requirements(外部接触) | チョークポイントへの prepend フック |

### core とアダプタの境界

- **core** = 観測の物理学(prepend ラッパー生成、TracePoint、コールスタック、帰属機構、三チャネルデータモデル、シリアライズ)
- **アダプタ** = 意味論(計装対象選択、エフェクト語彙の割り当て、テストライフサイクル接続)

**core は Rails にも RSpec にも依存しない。Gemfile レベルで分離を維持すること。**

### gem 間の安定契約: JSONL データスキーマ

gem 間の互換性は Ruby API ではなく `schema_version` 付き JSONL スキーマで担保する。スキーマ変更時は `schema_version` を上げ、`docs/schema.md` を同時更新する。

## 実装上の最重要ルール

1. **再入ガードを最初に実装する**(`Thread.current[:ethotrace_in_tracer]` フラグ)。これがないと Ethotrace 自身のコードがフックを発火して無限再帰する。

2. **stdlib フックも必ず公開アダプタ API 経由で実装する**(`dogfooding 原則`)。core が特権的な裏口を使うことは設計バグとして扱う。

3. **prepend ラッパーは挙動を一切変えない**: `rescue Exception => e; ... raise` で必ず再送出する。引数委譲(`*args, **kw, &blk`)、`frozen?`、`source_location`、backtrace 汚染最小化を守る。

4. **追跡テーブルは `end_call` で必ず掃除する**: GC 後の `object_id` 再利用対策。WeakRef は補助に留める。

5. **同一メソッドへの二重 wrap を禁止**: 計装レジストリで管理する。

6. **機微情報を記録しない**: ENV の value は記録しない(key のみ)。SQL 原文は既定 OFF。

## 実装ロードマップ

- **M0** スキャフォールド + スキーマ v1 確定
- **M1** prepend ラッパー + Tracker + CallContext + 再入ガード + JSONL ライター
- **M2** アダプタ API + stdlib アダプタ(ENV/Time/Random/IO) + 帰属機構 + エフェクトスパン
- **M3** TracePoint エンジン + 引数プロトコル観測
- **M4** ethotrace-rspec + マージ CLI
- **M5** ethotrace-rails (Railtie / Notifications / Zeitwerk)
- **M6** ethotrace-mcp + ethotrace-rbs

各マイルストーン末でテストグリーンを確認してからコミットすること。

## Git ワークフロー(ブランチ運用)

3層ブランチ構成で作業単位を区切る:

```
main                          # 安定版。milestone ブランチから統合する
 └ milestone/m0-scaffold      # ロードマップ(マイルストーン)単位の長命ブランチ
    └ feature/<topic>         # 機能単位の作業ブランチ
```

- **ロードマップブランチ**: `milestone/` プレフィックス + マイルストーンID(例: `milestone/m0-scaffold`, `milestone/m1-success-error`)。M0〜M6 ごとに `main` から切る。
- **feature ブランチ**: `feature/<topic>`。機能単位で当該 `milestone/*` から切り、**意味単位**でコミットする。
- **document ブランチ**: マイルストーンと無関係なドキュメント等の変更は `document`(または `document/<topic>`)ブランチを切り、PR で `main` にマージする。
- マージ方向: `feature/*` → `milestone/*` で作業単位を区切り、マイルストーン完了後に `milestone/*` → `main`。
- 各マイルストーン末でテストグリーンを確認してから `main` へ統合する。

### `main` 保護ルール(必須)

- **`main` への直接コミット・直接 push は禁止**。`main` は **GitHub 上の Pull Request マージ経由でのみ**更新する。
- すべての変更は `milestone/*` / `feature/*` / `document` 等のブランチ上で行い、PR を作成してマージする。

## テスト戦略

- ラッパー透過性(引数委譲・例外再送出・戻り値同一性)と再入ガードのテストを最優先で書く。
- フィクスチャに「既知の規約を持つ小さなクラス群」を用意し、観測結果 JSONL をゴールデンファイル比較する。
- ベンチ: `benchmark-ips` で TracePoint なし / `:call` のみ / `:c_call` 込みの3構成のオーバーヘッドを継続計測する。

## 観測結果の重要な仕様

観測結果は **observed contract(観測された下限)** であり、テストカバレッジに依存する。未実行パスの規約は含まれない。これは欠陥ではなく仕様であり、出力フォーマットに必ず明示する。

## Ruby バージョン

Ruby >= 3.2 を対象。キーワード引数・ブロック・`...` 委譲の Ruby 3.x セマンティクスに注意してテストで保証する。
