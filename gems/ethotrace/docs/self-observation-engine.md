# 自己観測レポート — ethotrace エンジン内部(BoxIsolation)

Ethotrace を **Ruby::Box で隔離して自分自身のエンジン内部に適用**して得た観測結果。
RSpec ベースの dogfood([self-observation.md](./self-observation.md))は NullIsolation で
動くため観測機構そのものを観測できないが、本レポートは **BoxIsolation**(設計資料 §4.8 /
§9 M5)で観測器(root)と観測対象(box 内 Ethotrace の別実体)を分離し、エンジン内部を
安全に観測する。集約には core 自身の `Ethotrace::Merge` を使う(自己適用)。

> **これは observed contract(観測された下限)である。** 実行したパスだけが反映される。
> 機械可読データ本体は同梱の [`self-observation-engine.jsonl`](./self-observation-engine.jsonl)
> (schema v1)。`gems/ethotrace/script/self_observe_engine.rb` で再生成できる。

## 観測環境

| 項目 | 値 |
|---|---|
| Ruby | 4.0.3(`RUBY_BOX=1` / main box) |
| Ethotrace | 0.1.0 |
| スキーマ | v1 |
| 隔離戦略 | BoxIsolation(`Ethotrace::Isolation::Box`) |
| 観測メソッド数 | 9 |

## なぜ Box が要るか / 何が観測できないか

- 観測器と観測対象が同一空間にいる NullIsolation では、エンジン内部を観測すると計装機構が
  計装対象になり自己言及で壊れる。Box は box 内 Ethotrace を root と**別実体**にしてこれを断つ
  (`box Tracker.object_id != root Tracker.object_id`)。
- **記録の活性パスは Box でも観測できない**(恒久的な床)。`Wrapper::SELF_DENY_LIST` が
  box を跨いでも次を計装対象から除外する(設計 §4.8 defense-in-depth):
  `Tracker` / `Wrapper` / `ReentryGuard` / `Collector` / `Diagnostics` / `ArgumentTable` / `Instrumentation` / `CallContext` / `ProtocolTracer`。
  本ハーネスでこれらの wrap が実際に拒否されることを確認している。

## 観測契約(エンジン内部)

観測メソッド: 9

| メソッド | 戻り値の型 | Requirements | 伝播例外 | samples |
|---|---|---|---|---|
| `AdapterRegistry.adapters` | Array | — | — | 2 |
| `AdapterRegistry.names` | Array | — | — | 1 |
| `AdapterRegistry.register` | Ethotrace::Adapters::Stdlib | — | — | 1 |
| `AdapterRegistry.reset!` | Array | — | — | 2 |
| `Instrumenter#wrap_method` | FalseClass \| TrueClass | — | — | 10 |
| `JSONLWriter#close` | NilClass | — | — | 1 |
| `JSONLWriter#closed?` | FalseClass | — | — | 1 |
| `JSONLWriter.open` | Ethotrace::JSONLWriter | `io.write`, `time.read` | — | 1 |
| `Merge.call` | Array | — | — | 1 |

## 所見

- **エンジン内部 9 メソッドの規約を、自己言及で壊さずに観測できた。** これは
  BoxIsolation がなければ得られない(Null の dogfood では観測機構を観測できない)。
- **`JSONLWriter.open` は `io.write` / `time.read` を要求する**(Ethotrace が自身の出力シンクの Requirements を観測した例)。
- **deny-list の床は健在。** 記録の活性パス(9 クラス)は Box でも wrap を拒否され、
  自己観測の対象にならない。これは欠陥ではなく設計(§4.8)。

---

*このファイルは `gems/ethotrace/script/self_observe_engine.rb` が生成した。*
