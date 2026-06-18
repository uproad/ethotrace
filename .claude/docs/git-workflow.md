# Git ワークフロー

## ブランチ運用

3層ブランチ構成で作業単位を区切る:

```
main                          # 安定版。milestone ブランチから統合する
 └ milestone/m0-scaffold      # ロードマップ（マイルストーン）単位の長命ブランチ
    └ feature/<topic>         # 機能単位の作業ブランチ
```

- **ロードマップブランチ**: `milestone/` プレフィックス + マイルストーンID（例: `milestone/m0-scaffold`, `milestone/m1-success-error`）。M0〜M8 ごとに `main` から切る。
- **feature ブランチ**: `feature/<topic>`。機能単位で当該 `milestone/*` から切り、**意味単位**でコミットする。
- **document ブランチ**: マイルストーンと無関係なドキュメント等の変更は `document`（または `document/<topic>`）ブランチを切り、PR で `main` にマージする。
- マージ方向: `feature/*` → `milestone/*` で作業単位を区切り、マイルストーン完了後に `milestone/*` → `main`。
- 各マイルストーン末でテストグリーンを確認してから `main` へ統合する。

## マイルストーンの標準作業手順（必須）

各マイルストーンは次の手順で進める。**この手順を標準とする。**

1. **機能分解**: マイルストーン開始時に、その中の項目を**機能ごとに分解**する（feature 単位の設計）。
2. **feature 実装 + PR**: 分解した機能単位で `feature/<topic>` ブランチを当該 `milestone/*` から
   切り、実装して**マイルストーンブランチへマージする PR** を作成する。
3. **マージを待たず継続**: ユーザーが出された PR を順次確認し、マージ可能ならマージする。この
   マージ作業は Claude Code の作業と**並列**で行う。**Claude Code は PR のマージを待たず、次の
   feature の実装へ進む**（スタック PR）。
4. **PR ブランチ自動削除に注意**: PR マージ時に GitHub の設定でマージ済み PR のリモートブランチが
   **自動削除される**。次の feature を切る・rebase する・スタックを積み直す際は、削除済みブランチを
   基底にしないよう、**最新の `milestone/*` を基点**にすること（必要に応じて `git fetch --prune`）。
5. **ドキュメント更新 PR**: マイルストーンの**全機能実装が完了したら**、ドキュメントを更新する PR を
   **マイルストーンブランチへ**出す。
6. **マイルストーン統合の合図**: ユーザーがすべての PR をチェックしてマイルストーンブランチへ
   マージし、その完了を Claude Code へ伝える。
7. **main への PR**: その合図を受けて、Claude Code が **`milestone/*` → `main`** の PR を作成する
   （`main` 保護ルールに従い、マージはユーザーが行う）。

## `main` 保護ルール（必須）

- **`main` への直接コミット・直接 push は禁止**。`main` は **GitHub 上の Pull Request マージ経由でのみ**更新する。
- すべての変更は `milestone/*` / `feature/*` / `document` 等のブランチ上で行い、PR を作成してマージする。

## コミット署名（必須）

- 全コミットを **SSH 署名（ed25519）** する。署名鍵は認証用 `id_rsa` と分離した署名専用鍵
  （`~/.ssh/id_ed25519_sign`）で、GitHub に signing key として登録済み（PR 上で **Verified** 表示）。
- git 設定はリポジトリローカルに適用済み（`commit.gpgsign=true` / `tag.gpgsign=true` /
  `gpg.format=ssh`）。**新規コミットは自動的に署名される**。
- 既存コミットを再署名する必要がある場合は `git rebase --exec "git commit --amend --no-edit -S" <base>` を使う。

## コミット・PR 運用（必須）

- コミットと PR の運用は `docs/commit-guidelines.md` に**必ず**従う。
- 要点: **1 PR = 1 機能単位、1 コミット = 1 意味単位**。作業前にコミット計画を立て、
  意味単位が完成するたびにコミットする。**最後の一括コミットは禁止**。
- 全コミットで**テストグリーン + ビルド可能**を維持する（`git bisect` 可能性。コミット前にテスト実行）。
- 振る舞いの変更とリファクタ、機械的変更と手書き変更、依存追加とその利用は**コミットを分離**する。
- コミットメッセージは Conventional Commits（`feat`/`fix`/`refactor`/`test`/`docs`/`chore`/`perf`/`ci` +
  scope は gem 名短縮形）。件名は「何をしたか」、本文に Why を書く。
- マージは **merge commit 方式のみ**（squash / rebase merge 禁止。コミットの物語を資産として残す）。
