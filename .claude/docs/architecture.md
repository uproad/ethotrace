# アーキテクチャ・実装ルール

## 観測機構（ハイブリッド）

| チャネル | 機構 |
|---|---|
| Success（戻り値） / Error（エスケープ例外） | `Module#prepend` ラッパー |
| 引数プロトコル（呼ばれたメソッド集合） | `TracePoint` （`:call`、`:c_call` はオプトイン） |
| Requirements（外部接触） | チョークポイントへの prepend フック |

## core とアダプタの境界

- **core** = 観測の物理学（prepend ラッパー生成、TracePoint、コールスタック、帰属機構、三チャネルデータモデル、シリアライズ）
- **アダプタ** = 意味論（計装対象選択、エフェクト語彙の割り当て、テストライフサイクル接続）

**core は Rails にも RSpec にも依存しない。Gemfile レベルで分離を維持すること。**

## gem 間の安定契約: JSONL データスキーマ

gem 間の互換性は Ruby API ではなく `schema_version` 付き JSONL スキーマで担保する。スキーマ変更時は `schema_version` を上げ、`docs/schema.md` を同時更新する。

## 実装上の最重要ルール

1. **再入ガードを最初に実装する**（`Thread.current[:ethotrace_in_tracer]` フラグ）。これがないと Ethotrace 自身のコードがフックを発火して無限再帰する。

2. **stdlib フックも必ず公開アダプタ API 経由で実装する**（`dogfooding 原則`）。core が特権的な裏口を使うことは設計バグとして扱う。

3. **prepend ラッパーは挙動を一切変えない**: `rescue Exception => e; ... raise` で必ず再送出する。引数委譲（`*args, **kw, &blk`）、`frozen?`、`source_location`、backtrace 汚染最小化を守る。

4. **追跡テーブルは `end_call` で必ず掃除する**: GC 後の `object_id` 再利用対策。WeakRef は補助に留める。

5. **同一メソッドへの二重 wrap を禁止**: 計装レジストリで管理する。

6. **機微情報を記録しない**: ENV の value は記録しない（key のみ）。SQL 原文は既定 OFF。

7. **自己適用は専用の隔離戦略で行う**: 再入ガード（ルール1）は「計装機構そのものが計装対象になる」自己言及を防げない。core は隔離を差し替え可能な isolation strategy（`NullIsolation` / `BoxIsolation` / `Stage0Bootstrap`）として実装し、Ruby::Box には依存しない。計装パスには自身の名前空間を除外する deny-list を defense-in-depth として常設する（設計資料 §4.8）。

## テスト戦略

- ラッパー透過性（引数委譲・例外再送出・戻り値同一性）と再入ガードのテストを最優先で書く。
- フィクスチャに「既知の規約を持つ小さなクラス群」を用意し、観測結果 JSONL をゴールデンファイル比較する。
- ベンチ: `benchmark-ips` で TracePoint なし / `:call` のみ / `:c_call` 込みの3構成のオーバーヘッドを継続計測する。

## 観測結果の重要な仕様

観測結果は **observed contract（観測された下限）** であり、テストカバレッジに依存する。未実行パスの規約は含まれない。これは欠陥ではなく仕様であり、出力フォーマットに必ず明示する。

## Ruby バージョン

Ruby >= 3.2 を対象。キーワード引数・ブロック・`...` 委譲の Ruby 3.x セマンティクスに注意してテストで保証する。
