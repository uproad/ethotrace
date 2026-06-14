# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## プロジェクト概要

**Ethotrace** は Ruby 向け動的型検査・シグネチャ解析システム。公称型(型名)ではなく、テスト実行中のメソッド呼び出しを監視して「振る舞い(プロトコル)」「伝播例外」「実行環境要件(Requirements)」を三チャネルで記録する。

設計思想: Effect-TS の `Effect<Success, Error, Requirements>` モデルに着想を得た三チャネル観測。詳細は `docs/ethotrace-design-handoff-v2.md` を参照(旧版は `docs/ethotrace-design-handoff-v1.md`。v2 で自己適用・隔離戦略・マイルストーン順序を改定)。

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

## コマンド

モノレポのルートから実行する。ルートの `Gemfile` が全 gem を束ね、`Rakefile` が全 gem の
spec と RuboCop を集約する。

```bash
# テスト実行(ルート集約)
bundle exec rake spec                       # 全 gem の全テスト
bundle exec rake                            # spec + RuboCop

# 単一ファイル / 行番号指定は -I で spec ディレクトリを load path に渡す
#(ルート .rspec の --require spec_helper を解決するため)
bundle exec rspec -I gems/ethotrace/spec gems/ethotrace/spec/ethotrace_spec.rb
bundle exec rspec -I gems/ethotrace/spec gems/ethotrace/spec/ethotrace_spec.rb:42

# Lint
bundle exec rake rubocop
bundle exec rubocop --autocorrect

# ベンチマーク(整備後)
bundle exec ruby benchmarks/overhead.rb     # TracePoint なし / :call / :c_call の3構成

# 観測データのマージ
bundle exec ethotrace merge tmp/ethotrace/*.jsonl -o ethotrace/observations.jsonl

# 自己観測を MCP サーバ(stdio / JSON-RPC)として起動する(既定で上記ストアを読む)
bundle exec ethotrace-mcp
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

7. **自己適用は専用の隔離戦略で行う**: 再入ガード(ルール1)は「計装機構そのものが計装対象になる」自己言及を防げない。core は隔離を差し替え可能な isolation strategy(`NullIsolation` / `BoxIsolation` / `Stage0Bootstrap`)として実装し、Ruby::Box には依存しない。計装パスには自身の名前空間を除外する deny-list を defense-in-depth として常設する(設計資料 §4.8)。

## 実装ロードマップ

順序の意図(v2 で改定): **M4 完了時点で「RSpec でテストされている Ethotrace 自身」が最初の実用検査対象になる**ため、M5 で自己適用(self-hosting)を達成し、M6 で MCP を**先に**作る。これにより以降の開発は Claude Code が MCP 経由で Ethotrace の自己観測結果(各メソッドの規約・例外・Requirements)を参照しながら進む——ツールが自分自身の開発を支援するブートストラップループに入る。Rails アダプタ以降はこのループの恩恵を受けて実装する(設計資料 §9)。

- **M0** スキャフォールド + スキーマ v1 確定 ✅
- **M1** prepend ラッパー + Tracker + CallContext + 再入ガード + JSONL ライター ✅
- **M2** アダプタ API + stdlib アダプタ(ENV/Time/Random/IO) + 帰属機構 + エフェクトスパン ✅
- **M3** TracePoint エンジン + 引数プロトコル観測 ✅
- **M4** ethotrace-rspec + マージ CLI ✅
- **M5** 自己適用(self-hosting)+ 隔離戦略: isolation strategy 抽象(`NullIsolation` / `BoxIsolation` / `Stage0Bootstrap`)、collector/probe 分離、検証実験 E1〜E6(設計資料 §4.8)、CI dogfooding ジョブ(Ruby 4.0 + `RUBY_BOX=1`、experimental のため allow-failure)
- **M6** ethotrace-mcp ✅(ブートストラップループの起点。自己観測データを読むクエリを MCP ツールとして公開)
- **M7** ethotrace-rails (Railtie / Notifications / Zeitwerk。BoxIsolation 併用は当面サポート外、`NullIsolation` で解析)
- **M8** ethotrace-rbs(protocol → RBS `interface` 投影。例外・Requirements は投影不可のため欠落を明記)

各マイルストーン末でテストグリーンを確認してからコミットすること。**M6 完了後は開発サイクルに自己観測を組み込む**: テスト実行 → `ethotrace merge` で自己観測更新 → 実装/リファクタ前に `ethotrace-mcp` で対象メソッドの規約・例外・Requirements を確認、というループを標準ワークフローとする。

### 自己観測ループ(M6 以降の標準ワークフロー)

M6 で `ethotrace-mcp` が完成し、ブートストラップループが使えるようになった。実装・リファクタの前に、対象メソッドの**観測された規約**(プロトコル・戻り値・伝播例外・Requirements)を MCP 経由で確認する。

1. **自己観測データを更新**: `ethotrace-rspec`(M4)で観測対象を設定したスイートを実行すると、
   ワーカーごとに `tmp/ethotrace/<session>.jsonl`(生ログ)が出る。これをマージ済みストアへ統合する。
   ```bash
   # spec_helper 等で Ethotrace::RSpec.setup { |c| c.observe Ethotrace::Merge, ... } を設定し spec 実行後:
   bundle exec ethotrace merge tmp/ethotrace/*.jsonl -o ethotrace/observations.jsonl
   ```
   (core 自身のスイートを常時観測する dogfood ジョブの常設は follow-up。当面は対象を絞って観測する。)
2. **MCP サーバを登録**(初回のみ): `.mcp.json.example` を `.mcp.json` にコピーすると、Claude Code が
   `bundle exec ethotrace-mcp` をプロジェクトスコープの MCP サーバとして起動する(既定で
   `ethotrace/observations.jsonl` を読む)。Claude Code 以外からは `bundle exec ethotrace-mcp` を
   stdio クライアントに繋ぐ。
3. **規約を参照してから実装する**: 公開ツール — `lookup_method`(1 メソッドの全規約)/ `pure_methods`
   (R=∅)/ `flaky_suspects`(`time.read`/`random.read` 等の非決定性)/ `requiring`(`db.query` 等の
   エフェクト)/ `methods_raising` ・ `exceptions_of`(伝播例外)/ `param_protocol`(引数のプロトコル)/
   `list_methods`。返る規約は **observed contract(テストで実行されたパスの下限)** であり、未実行パスは
   含まれない。MCP クエリで不足を感じた点は `ethotrace-mcp` の仕様改善としてフィードバックする(設計資料 §9)。

> 観測データ(`ethotrace/observations.jsonl`・`tmp/ethotrace/`)は再生成可能なため**コミットしない**(`.gitignore` 済み)。

## Git ワークフロー(ブランチ運用)

3層ブランチ構成で作業単位を区切る:

```
main                          # 安定版。milestone ブランチから統合する
 └ milestone/m0-scaffold      # ロードマップ(マイルストーン)単位の長命ブランチ
    └ feature/<topic>         # 機能単位の作業ブランチ
```

- **ロードマップブランチ**: `milestone/` プレフィックス + マイルストーンID(例: `milestone/m0-scaffold`, `milestone/m1-success-error`)。M0〜M8 ごとに `main` から切る。
- **feature ブランチ**: `feature/<topic>`。機能単位で当該 `milestone/*` から切り、**意味単位**でコミットする。
- **document ブランチ**: マイルストーンと無関係なドキュメント等の変更は `document`(または `document/<topic>`)ブランチを切り、PR で `main` にマージする。
- マージ方向: `feature/*` → `milestone/*` で作業単位を区切り、マイルストーン完了後に `milestone/*` → `main`。
- 各マイルストーン末でテストグリーンを確認してから `main` へ統合する。

### マイルストーンの標準作業手順(必須)

各マイルストーンは次の手順で進める。**この手順を標準とする。**

1. **機能分解**: マイルストーン開始時に、その中の項目を**機能ごとに分解**する(feature 単位の設計)。
2. **feature 実装 + PR**: 分解した機能単位で `feature/<topic>` ブランチを当該 `milestone/*` から
   切り、実装して**マイルストーンブランチへマージする PR** を作成する。
3. **マージを待たず継続**: ユーザーが出された PR を順次確認し、マージ可能ならマージする。この
   マージ作業は Claude Code の作業と**並列**で行う。**Claude Code は PR のマージを待たず、次の
   feature の実装へ進む**(スタック PR)。
4. **PR ブランチ自動削除に注意**: PR マージ時に GitHub の設定でマージ済み PR のリモートブランチが
   **自動削除される**。次の feature を切る・rebase する・スタックを積み直す際は、削除済みブランチを
   基底にしないよう、**最新の `milestone/*` を基点**にすること(必要に応じて `git fetch --prune`)。
5. **ドキュメント更新 PR**: マイルストーンの**全機能実装が完了したら**、ドキュメントを更新する PR を
   **マイルストーンブランチへ**出す。
6. **マイルストーン統合の合図**: ユーザーがすべての PR をチェックしてマイルストーンブランチへ
   マージし、その完了を Claude Code へ伝える。
7. **main への PR**: その合図を受けて、Claude Code が **`milestone/*` → `main`** の PR を作成する
   (`main` 保護ルールに従い、マージはユーザーが行う)。

### `main` 保護ルール(必須)

- **`main` への直接コミット・直接 push は禁止**。`main` は **GitHub 上の Pull Request マージ経由でのみ**更新する。
- すべての変更は `milestone/*` / `feature/*` / `document` 等のブランチ上で行い、PR を作成してマージする。

### コミット署名(必須)

- 全コミットを **SSH 署名(ed25519)** する。署名鍵は認証用 `id_rsa` と分離した署名専用鍵
  (`~/.ssh/id_ed25519_sign`)で、GitHub に signing key として登録済み(PR 上で **Verified** 表示)。
- git 設定はリポジトリローカルに適用済み(`commit.gpgsign=true` / `tag.gpgsign=true` /
  `gpg.format=ssh`)。**新規コミットは自動的に署名される**。
- 既存コミットを再署名する必要がある場合は `git rebase --exec "git commit --amend --no-edit -S" <base>` を使う。

### コミット・PR 運用(必須)

- コミットと PR の運用は `docs/commit-guidelines.md` に**必ず**従う。
- 要点: **1 PR = 1 機能単位、1 コミット = 1 意味単位**。作業前にコミット計画を立て、
  意味単位が完成するたびにコミットする。**最後の一括コミットは禁止**。
- 全コミットで**テストグリーン + ビルド可能**を維持する(`git bisect` 可能性。コミット前にテスト実行)。
- 振る舞いの変更とリファクタ、機械的変更と手書き変更、依存追加とその利用は**コミットを分離**する。
- コミットメッセージは Conventional Commits(`feat`/`fix`/`refactor`/`test`/`docs`/`chore`/`perf`/`ci` +
  scope は gem 名短縮形)。件名は「何をしたか」、本文に Why を書く。
- マージは **merge commit 方式のみ**(squash / rebase merge 禁止。コミットの物語を資産として残す)。

## テスト戦略

- ラッパー透過性(引数委譲・例外再送出・戻り値同一性)と再入ガードのテストを最優先で書く。
- フィクスチャに「既知の規約を持つ小さなクラス群」を用意し、観測結果 JSONL をゴールデンファイル比較する。
- ベンチ: `benchmark-ips` で TracePoint なし / `:call` のみ / `:c_call` 込みの3構成のオーバーヘッドを継続計測する。

## 観測結果の重要な仕様

観測結果は **observed contract(観測された下限)** であり、テストカバレッジに依存する。未実行パスの規約は含まれない。これは欠陥ではなく仕様であり、出力フォーマットに必ず明示する。

## Ruby バージョン

Ruby >= 3.2 を対象。キーワード引数・ブロック・`...` 委譲の Ruby 3.x セマンティクスに注意してテストで保証する。
