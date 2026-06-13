# Ruby::Box セマンティクス検証結果(設計資料 v2 §4.8 / 実験 E1〜E6)

Ethotrace の自己適用(self-hosting)は、観測者と観測対象が同一クラス実体を共有して
汚染する問題を `Ruby::Box`(Ruby 4.0 experimental)で実体分離する設計に依る。本書は
その前提を実環境で裏取りした結果と、隔離戦略 `BoxIsolation` 実装(M5 feature 4)への
含意を記録する。

> **注意**: `Ruby::Box` は experimental であり、挙動は将来変わりうる。本結果は下記の
> 検証バージョンに対するスナップショットである。Ruby を更新したら必ず再検証すること。

## 検証環境

- **Ruby 4.0.3 (2026-04-21 revision 85ddef263a) +PRISM [x86_64-linux]**
- `RUBY_BOX=1`(これが無いと `Ruby::Box.new` は `Ruby::Box.enabled? == false` で無効)

## 再現方法

```bash
# 手動の実験ハーネス(各実験の生の値を表示)
RUBY_BOX=1 ruby gems/ethotrace/script/box_experiments.rb

# 不変条件を固定する回帰 spec(RUBY_BOX=1 が無いと skip)
RUBY_BOX=1 bundle exec rspec -I gems/ethotrace/spec \
  gems/ethotrace/spec/isolation/box_semantics_spec.rb
```

## API メモ

`Ruby::Box`(インスタンス): `eval` / `load` / `require` / `require_relative` /
`load_path` / `main?` / `root?`。クラス: `current` / `enabled?` / `main` / `root`。

- `box.eval(src)` は **引数1個**(locals/binding を渡せない)。root のオブジェクトを box に
  注入するには、box 側に橋渡しメソッドを定義し、root から root オブジェクトを引数で渡して
  呼ぶ(下記 E1/E3)。box の定数は `box.eval("Const")` でも `box::Const` でも取得できる(E2)。

## 実験結果

| 実験 | 問い | 結果(main box) | 含意 |
|---|---|---|---|
| **E1** | root の TracePoint は box 内 `:call` を観測でき、`tp.self` の同一性が使えるか | **Yes**。box 内呼び出し(`ping`/`touch`)を観測し、`tp.self.object_id` が root の追跡テーブルと一致 | 引数プロトコル観測(TracePoint)は **root 側のままで box 越境可** |
| **E2** | root から box 内定数へアクセスする手段 | `box.eval("Const")` / `box::Const` の両方が機能 | root collector が box 内の対象クラスへ到達できる |
| **E3** | root オブジェクトを box メソッドへ渡すとどちらの空間で実行されるか。Thread-local は越境するか | root 定義で実行。Thread-local は同一スレッドなら box を跨いで可視 | **再入ガード(Thread-local)は box を跨いで有効**。collector を bridge 注入できる |
| **E4** | box にロードした `Ethotrace::Tracker` は root と別実体か | **main box では別実体(分離成立)**。ただし系譜依存(下記) | 計装機構が計装対象になる自己言及汚染が構造的に解決しうる |
| **E5** | root の prepend フックは box 内コードから見えるか | **main box では見えない**(box は core クラスの独自ビュー)。系譜依存(下記) | Requirements / Success・Error 用の **prepend フックは probe 側(box 内)必須** |
| **E6** | box 生成のオーバーヘッド | 約 **0.017 ms / box**、**約 12.8 KB / box**(memsize 増分) | 軽微。対象 gem 単位で box を起てても実用的 |

## 最重要の発見: box 系譜とロード順への依存(E4・E5)

E4(実体分離)と E5(core クラスの独自ビュー)の結果は **「現在の box が何か」に依存する**。
`Ruby::Box.current` を観察すると:

| 実行文脈 | `Ruby::Box.current` | E4 分離 | E5 root prepend 波及 |
|---|---|---|---|
| 生 `RUBY_BOX=1 ruby script.rb` | `#<Ruby::Box:_,user,main>` `main?=true` | **する** | **しない**(独自ビュー) |
| `RUBY_BOX=1 bundle exec rspec` | `#<Ruby::Box:_,root>` `main?=false root?=true` | **しない**(共有) | **する**(波及) |

メカニズム: **main box から作った子 box** は、ロード済みライブラリ(ethotrace)や core クラスの
**独自スナップショット**を持つため分離する。一方、**既に ethotrace をロード済みの非 main box**
(RUBY_BOX=1 下の RSpec ランナーはこの `root` box 内で動く)から作った子 box は、親の定義を
**共有**するため `box.require("ethotrace")` は `false`(既ロード)を返し、`Tracker` も同一実体に
なる。同様に prepend フックも親と共有されるため box 内へ波及する。

これは flaky ではなく **再現性のある系譜依存**である。回帰 spec
(`box_semantics_spec.rb`)は E4・E5 を `Ruby::Box.current.main?` で分岐させ、両文脈の
挙動を不変条件として固定している。

## 設計への含意(M5 feature 2〜4)

1. **プロトコル観測は root 側 TracePoint のままでよい**(E1)。probe 側 TracePoint 化は不要。
   設計資料 §11-8 / E1 の「拾わない場合は probe 側へ」の分岐は**不要側に確定**。
2. **Requirements・Success/Error の prepend フックは probe 側(box 内)に張る**(E5)。
   collector(Tracker・帰属・JSONL)は root に置き、probe から bridge 経由で通知する。
   → collector / probe 分離(feature 3)はこの分界をそのまま実装する。
3. **再入ガード・コールスタックは Thread-local のまま box を跨いで機能する**(E3)。
   box ごとに guard 状態を複製する必要はない(同一スレッド前提)。
4. **`BoxIsolation`(feature 4)はロード順・box 系譜を制御しなければならない**(E4・E5)。
   「テストハーネス(非 main box)の中で素朴に `Ruby::Box.new` して ethotrace を require」
   しても分離しない。観測対象 gem を**子 box に新規ロード**し、collector 側 ethotrace は
   親/ main box 側に置いて bridge する、という構成が要る。この制御方法の確定は feature 4 の
   主要タスク。

## Ruby::Box 既知の制約(§4.8 の再掲 + 本検証時点)

- experimental。CI の dogfooding ジョブ(Ruby 4.0 + `RUBY_BOX=1`)は **allow-failure** とする。
- セキュリティサンドボックスではない(名前空間隔離のみ)。観測用途には十分。
- `RUBY_BOX=1` 下でネイティブ拡張 gem のインストールが失敗しうる。回避: フラグ無しで
  `bundle install` し、実行時のみ `RUBY_BOX=1` を付与。
- ENV 実値・FD・GC・シグナル等のプロセスグローバル資源は box 間で共有(隔離は定義のみ)。
- ActiveSupport core_ext の一部に互換性問題 → **Rails アダプタ + BoxIsolation の併用は当面サポート外**。
