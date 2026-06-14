# Ethotrace::MCP

Ethotrace の観測結果(`observations.jsonl`)を **MCP サーバ**として公開する gem。
「このメソッドは引数に何を要求するか・何を返すか・どんな例外を投げうるか・どんな
実行環境(Requirements)を必要とするか」を MCP ツールとして AI エージェントへ提供する。

観測プロセス(core + アダプタ)とは**完全に分離**したデータ消費者であり、計装は一切
ロードしない。core とは `schema_version` 付き JSONL スキーマ(`docs/schema.md`)を介して
結合する。

> 第一のユーザーは Ethotrace を開発する Claude Code 自身。自己観測データを MCP 経由で
> 参照しながら開発を進めるブートストラップループの起点になる(設計資料 §9 / M6)。

モノレポ全体の概要・設計は親リポジトリの `README.md` と
`docs/ethotrace-design-handoff-v2.md` を参照。

## 開発

```bash
# モノレポルートから
bundle exec rake spec      # 全 gem のテスト
```
