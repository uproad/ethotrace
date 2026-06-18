# コマンドリファレンス

モノレポのルートから実行する。ルートの `Gemfile` が全 gem を束ね、`Rakefile` が全 gem の
spec と RuboCop を集約する。

```bash
# テスト実行(ルート集約)
bundle exec rake spec                       # 全 gem の全テスト
bundle exec rake                            # spec + RuboCop

# 単一ファイル / 行番号指定は -I で spec ディレクトリを load path に渡す
#（ルート .rspec の --require spec_helper を解決するため）
bundle exec rspec -I gems/ethotrace/spec gems/ethotrace/spec/ethotrace_spec.rb
bundle exec rspec -I gems/ethotrace/spec gems/ethotrace/spec/ethotrace_spec.rb:42

# Lint
bundle exec rake rubocop
bundle exec rubocop --autocorrect

# ベンチマーク（整備後）
bundle exec ruby benchmarks/overhead.rb     # TracePoint なし / :call / :c_call の3構成

# 観測データのマージ
bundle exec ethotrace merge tmp/ethotrace/*.jsonl -o ethotrace/observations.jsonl

# 自己観測を MCP サーバ（stdio / JSON-RPC）として起動する（既定で上記ストアを読む）
bundle exec ethotrace-mcp
```
