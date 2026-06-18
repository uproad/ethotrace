# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## プロジェクト概要

**Ethotrace** は Ruby 向け動的型検査・シグネチャ解析システム。テスト実行中のメソッド呼び出しを監視して「振る舞い（プロトコル）」「伝播例外」「実行環境要件（Requirements）」を三チャネルで記録する。設計思想は `docs/ethotrace-design-handoff-v2.md` を参照。

## Gem 構成（モノレポ）

実在する gem（`gems/` 配下）:

```
gems/ethotrace          # core: 観測エンジン + stdlib アダプタ + JSONL ライター + マージ CLI
gems/ethotrace-rspec    # RSpec ライフサイクル接続
gems/ethotrace-mcp      # MCP サーバ（観測プロセスと完全分離）
```

計画中（未作成。ロードマップ上の将来マイルストーン — `.claude/docs/roadmap.md` 参照）:

```
ethotrace-minitest      # Minitest 版
ethotrace-rails         # Railtie / ActiveSupport::Notifications / Zeitwerk 連携（M7）
ethotrace-rbs           # RBS interface への投影（M8）
```

## 活動別ナレッジ（必要時に Read すること）

知識は活動ロール別に分割されている。**該当する活動を行う前に対応ファイルを Read で読み込むこと。**

| いつ読むか | ファイル |
|---|---|
| テスト実行・lint・コマンド実行 | `.claude/docs/commands.md` |
| コード実装・設計判断・テスト作成 | `.claude/docs/architecture.md` |
| マイルストーン計画・自己観測・次の作業決定 | `.claude/docs/roadmap.md` |
| ブランチ操作・コミット・PR 作成 | `.claude/docs/git-workflow.md` |

複数の活動にまたがる場合は該当するファイルをすべて読む。
