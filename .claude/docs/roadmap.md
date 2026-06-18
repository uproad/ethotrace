# 実装ロードマップ

順序の意図（v2 で改定）: **M4 完了時点で「RSpec でテストされている Ethotrace 自身」が最初の実用検査対象になる**ため、M5 で自己適用（self-hosting）を達成し、M6 で MCP を**先に**作る。これにより以降の開発は Claude Code が MCP 経由で Ethotrace の自己観測結果（各メソッドの規約・例外・Requirements）を参照しながら進む——ツールが自分自身の開発を支援するブートストラップループに入る。Rails アダプタ以降はこのループの恩恵を受けて実装する（設計資料 §9）。

- **M0** スキャフォールド + スキーマ v1 確定 ✅
- **M1** prepend ラッパー + Tracker + CallContext + 再入ガード + JSONL ライター ✅
- **M2** アダプタ API + stdlib アダプタ（ENV/Time/Random/IO） + 帰属機構 + エフェクトスパン ✅
- **M3** TracePoint エンジン + 引数プロトコル観測 ✅
- **M4** ethotrace-rspec + マージ CLI ✅
- **M5** 自己適用（self-hosting）+ 隔離戦略: isolation strategy 抽象（`NullIsolation` / `BoxIsolation` / `Stage0Bootstrap`）、collector/probe 分離、検証実験 E1〜E6（設計資料 §4.8）、CI dogfooding ジョブ（Ruby 4.0 + `RUBY_BOX=1`、experimental のため allow-failure）
- **M6** ethotrace-mcp ✅（ブートストラップループの起点。自己観測データを読むクエリを MCP ツールとして公開）
- **M7** ethotrace-rails （Railtie / Notifications / Zeitwerk。BoxIsolation 併用は当面サポート外、`NullIsolation` で解析）
- **M8** ethotrace-rbs（protocol → RBS `interface` 投影。例外・Requirements は投影不可のため欠落を明記）

各マイルストーン末でテストグリーンを確認してからコミットすること。**M6 完了後は開発サイクルに自己観測を組み込む**: テスト実行 → `ethotrace merge` で自己観測更新 → 実装/リファクタ前に `ethotrace-mcp` で対象メソッドの規約・例外・Requirements を確認、というループを標準ワークフローとする。

## 自己観測ループ（M6 以降の標準ワークフロー）

M6 で `ethotrace-mcp` が完成し、ブートストラップループが使えるようになった。実装・リファクタの前に、対象メソッドの**観測された規約**（プロトコル・戻り値・伝播例外・Requirements）を MCP 経由で確認する。

1. **自己観測データを更新**: `ethotrace-rspec`（M4）で観測対象を設定したスイートを実行すると、
   ワーカーごとに `tmp/ethotrace/<session>.jsonl`（生ログ）が出る。これをマージ済みストアへ統合する。
   ```bash
   # spec_helper 等で Ethotrace::RSpec.setup { |c| c.observe Ethotrace::Merge, ... } を設定し spec 実行後:
   bundle exec ethotrace merge tmp/ethotrace/*.jsonl -o ethotrace/observations.jsonl
   ```
   （core 自身のスイートを常時観測する dogfood ジョブの常設は follow-up。当面は対象を絞って観測する。）
2. **MCP サーバを登録**（初回のみ）: `.mcp.json.example` を `.mcp.json` にコピーすると、Claude Code が
   `bundle exec ethotrace-mcp` をプロジェクトスコープの MCP サーバとして起動する（既定で
   `ethotrace/observations.jsonl` を読む）。Claude Code 以外からは `bundle exec ethotrace-mcp` を
   stdio クライアントに繋ぐ。
3. **規約を参照してから実装する**: 公開ツール — `lookup_method`（1 メソッドの全規約）/ `pure_methods`
   （R=∅）/ `flaky_suspects`（`time.read`/`random.read` 等の非決定性）/ `requiring`（`db.query` 等の
   エフェクト）/ `methods_raising` ・ `exceptions_of`（伝播例外）/ `param_protocol`（引数のプロトコル）/
   `list_methods`。返る規約は **observed contract（テストで実行されたパスの下限）** であり、未実行パスは
   含まれない。MCP クエリで不足を感じた点は `ethotrace-mcp` の仕様改善としてフィードバックする（設計資料 §9）。

> 観測データ（`ethotrace/observations.jsonl`・`tmp/ethotrace/`）は再生成可能なため**コミットしない**（`.gitignore` 済み）。
