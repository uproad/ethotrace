# 検証用サンプル — 複雑なメソッドを高カバレッジ spec で観測する

戻り値が条件で複数の型(`nil` / `Integer` / 独自クラス…)に分岐し、複数のエラーが
条件で送出され、引数の数や呼ぶメソッドにパターンがあり、依存先も複数あるメソッドを、
**複雑さ 3 段階**で用意した。各メソッドには**内部の全条件を通る高カバレッジ spec**が
付いており、`ethotrace-rspec` 経由で spec を走らせると三チャネルの観測が書き出される。

## 構成

```
examples/verification/
  lib/
    level1_gate.rb        # Gate#admit       — 戻り値 3 / エラー 1 / 依存 0
    level2_pricing.rb     # Pricing#quote    — 戻り値 5 / エラー 3 / 依存 2(ENV/Time)
    level3_dispatcher.rb  # Dispatcher#call  — 戻り値 10 / エラー 7 / 依存 3(ENV/Time/Random)
  spec/
    spec_helper.rb        # 計装をスイートで一度だけ設置し、writer を spec ごとに差し替える
    support/fixtures.rb   # 引数に渡すダックタイプのコラボレータ(def アクセサ)
    level1_gate_spec.rb   # 全分岐を通す
    level2_pricing_spec.rb
    level3_dispatcher_spec.rb
  result/                 # 観測結果(spec ファイル = レベルごとに 1 つの JSONL)
    level1_gate_spec.jsonl
    level2_pricing_spec.jsonl
    level3_dispatcher_spec.jsonl
```

観測結果は `spec/` の横の `result/` に **spec ファイル(= 各レベル)ごと** に書き出される。
計装(prepend ラッパー・Requirements フック・引数プロトコルの TracePoint)はスイートで
一度だけ設置し、書き出し先の writer だけを spec ファイルごとに購読/解除して切り替える。
こうすると同じクラスを再 wrap せずに済み(レコードの二重化を回避)、レベル単位で
観測契約を切り分けられる。`result/` の JSONL はサンプルの成果物としてコミットしている
(`site.path` は移植性のためリポジトリ相対パスへ正規化済み)。

## 実行

```bash
# spec を実行(全分岐グリーン)。observation が result/ に spec ファイルごとに書き出される。
bundle exec rspec -I examples/verification/spec examples/verification/spec

# レベル別に観測サマリ(メソッドごと 1 行)を見る
bundle exec ethotrace view examples/verification/result/level3_dispatcher_spec.jsonl

# 詳細(三チャネル + 引数プロトコル)
bundle exec ethotrace view examples/verification/result/level3_dispatcher_spec.jsonl -m "Dispatcher#call"

# 全レベルをまとめて見る / 1 ファイルへ統合する(view / merge とも複数ファイルを取る)
bundle exec ethotrace view examples/verification/result/*.jsonl
bundle exec ethotrace merge examples/verification/result/*.jsonl -o examples/verification/result/all.jsonl
```

## 複雑さ Level 3 の観測結果(`Dispatcher#call`)

`command` ひとつで戻り値の型もエラーも依存先も総取り替えになる「頭が痛くなる」メソッド。
それを高カバレッジ spec で 1 回走らせるだけで、観測契約がここまで埋まる:

```text
Dispatcher#call  (instance)
  return (Success):
    TrueClass / FalseClass / String / Integer / Float /
    Symbol / Result / Array / Hash / NilClass        ← 10 クラス

  args (protocol):
    [0] command : Symbol
    [1] (positional) : Symbol, Integer, Blueprint, Wallet
        fields(arity 0)                              ← Blueprint に呼ばれた振る舞い
        balance(arity 0)                             ← Wallet に呼ばれた振る舞い

  errors (Error):
    KeyError          [direct]
    ArgumentError     [direct]
    ZeroDivisionError [direct]
    TypeError         [direct]
    RuntimeError      [inherited from Ledger#charge]  ← 被観測 callee からの伝播
    DispatchError     [direct]
    UnknownCommand    [direct]

  requirements:
    time.read    [read, direct]  {}
    random.read  [read, direct]  {}
    env.read     [read, direct]  {"key":"GREETING"}
```

読みどころ:

- **複数戻り値型の集約**: 1 メソッドが返しうる 10 クラスがすべて `return` に並ぶ。
- **エラーの帰属**: 各メソッドが直接送出した例外は `direct`。`Ledger#charge` が送出して
  `Dispatcher#call` をエスケープした `RuntimeError` は `inherited from Ledger#charge` と記録され、
  「どこで起きてどこを通り抜けたか」が分かる。
- **可変長引数のプロトコル**: `*args` に渡った各オブジェクトの振る舞いが位置をまたいで
  集約される。公称型(`Blueprint` / `Wallet`)は併記しつつ、契約は呼ばれたメソッド集合
  (`fields` / `balance`)で表す。
- **複数依存の畳み込み**: `:env` / `:stamp` / `:dice` のそれぞれで触れた外部世界が
  Requirements にまとまる(ENV は **key のみ**、値は記録しない)。

## 重要な注意: 依存をモックすると Requirement は観測されない

Ethotrace は**実行を観測する**ため、依存をテストダブルで差し替えると、その下の
チョークポイント(`Time.now` 等への prepend フック)が走らず、**Requirement は記録されない**。
本サンプルの `Pricing` では `Time.now` を直接 stub せず、判定用の private メソッド
`happy_hour?` を差し替えて分岐を確定化しつつ、別に「実時計を読む」例を 1 つ置いて
`time.read` を観測させている(`level2_pricing_spec.rb` 参照)。

## 観測は「観測された下限」

観測契約はテストが通った分岐の**和集合**であり、カバレッジに依存する。未実行の分岐は
契約に現れない。だからこそ、ここでは全分岐を通す高カバレッジ spec とセットにしている。
カバレッジを落とすと観測契約も痩せることは、spec の一部を `xit` にして観測を見比べると確かめられる。
