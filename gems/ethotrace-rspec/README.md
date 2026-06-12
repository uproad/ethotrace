# ethotrace-rspec

[Ethotrace](https://github.com/uproad/ethotrace) の **RSpec ライフサイクル接続アダプタ**。

RSpec のスイート開始/終了に Ethotrace の観測セッション(`Ethotrace::Session`)を
接続し、テストワーカーごとに `tmp/ethotrace/<session>.jsonl` を書き出す。観測の
物理学(prepend ラッパー・TracePoint・三チャネルデータモデル)は core(`ethotrace`)
が担い、本 gem は**意味論**(テストライフサイクルへの接続)に徹する。

> モノレポ構成のアダプタ gem。core は RSpec に依存せず、依存方向は
> `ethotrace-rspec → ethotrace` の一方向のみ。

## ステータス

M4 スキャフォールド段階。RSpec への実際のライフサイクル接続(セッションの
自動開始/終了・対象選択ヘルパ)は後続 feature で実装する。

## License

MIT License.
