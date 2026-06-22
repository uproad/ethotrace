# コントリビューションガイド

*Read this in [English](CONTRIBUTING.md).*

Ethotrace への貢献に興味を持っていただきありがとうございます。このドキュメントは、
Issue・Pull Request を出す際の手順と規約をまとめたものです。

## はじめに

- バグ報告・機能提案は **Issue** からお願いします。再現手順・期待する挙動・実際の挙動を
  含めていただけると助かります。
- セキュリティ上の脆弱性は Issue ではなく、非公開の窓口から報告してください
  （[`SECURITY.md`](SECURITY.md) を参照）。
- 大きめの変更を予定している場合は、実装前に Issue で方針を相談していただけると、
  手戻りを防げます。

## 開発環境

Ruby >= 3.2 が必要です。ルートの `Gemfile` がモノレポ内の全 gem を束ねています。

```bash
bundle install          # 依存解決
bundle exec rake        # 全 gem の spec + RuboCop（CI 相当のフルチェック）
bundle exec rake spec   # テストのみ
bundle exec rake rubocop
```

**すべてのコミットでテストグリーン + RuboCop パス + ビルド可能**を維持してください
（`git bisect` 可能性のため）。

## ブランチと Pull Request

- `main` は保護されており、**直接 push はできません**。変更はすべて Pull Request 経由で
  `main` にマージされます。
- 外部コントリビューターはリポジトリを **fork** し、トピックブランチで作業して `main` 向けの
  PR を出してください。
- マージは **merge commit 方式のみ**です（squash / rebase merge は無効）。意味のあるコミットを
  積み上げた履歴をプロジェクトの資産として残すためです。

## コミット規約

このプロジェクトでは **コミットログを「レビュアーが変更を理解するための物語」** として
重視しています。詳細な規約は [`docs/commit-guidelines.md`](docs/commit-guidelines.md) に
定めてあり、**PR を出す前に必ず一読してください**。要点のみ抜粋します。

- **1 PR = 1 機能単位、1 コミット = 1 意味単位**。作業の最後にまとめて 1 コミットにするのは
  規約違反です。意味単位が完成するたびにコミットしてください。
- コミットメッセージは [Conventional Commits](https://www.conventionalcommits.org/) 準拠
  （`feat` / `fix` / `refactor` / `test` / `docs` / `chore` / `perf` / `ci`）。scope は gem 名の
  短縮形（`core` / `rspec` / `mcp` / `rbs` など）。
- 件名は「何をしたか」、本文に「なぜか（Why）」を書く。
- **振る舞いの変更とリファクタリング**、**機械的変更と手書きの変更**、**依存追加とその利用**は
  コミットを分離する。
- テストは対応する実装と同じコミットに含める。

## コーディング規約

- コード中の自然言語は、識別子・文字列リテラル・ログ/例外メッセージ・spec の説明文
  (`it` / `describe`)などすべて英語で書きます。唯一の例外はコメントで、コメントは言語を
  問いません。
- スタイルは RuboCop に従います（`bundle exec rake rubocop`）。

## ライセンス

コントリビュートされたコードは、本プロジェクトと同じ [MIT ライセンス](LICENSE) の下で
公開されることに同意したものとみなされます。
