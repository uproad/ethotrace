# frozen_string_literal: true

# Ethotrace 自身を Ethotrace で観測する dogfooding 注入ファイル。
#
# RSpec の `-r`(--require)で読み込み、`Ethotrace::RSpec.setup` を通じて
# 観測セッションをスイートに接続する。観測結果はワーカーごとに
# `tmp/dogfood/<session>.jsonl` へ書き出し、後で `ethotrace merge` で統合する。
#
#   bundle exec rspec -r ./script/dogfood/observe.rb -I gems/<gem>/spec <safe specs>
#
# **観測対象はオフラインのデータ処理層・純クエリ層に限定する。** 観測エンジン
# 本体(Wrapper/Tracker/Session/TracePoint 等)を観測すると、ラップ呼び出しが
# 共有スタックや購読者をテスト中に変化させてエンジン自身の単体テストを壊し、
# 自己言及で SystemStackError に至る(設計資料 §4.8 / CLAUDE.md ルール7)。
# エンジン本体の自己観測は box 隔離(M5)が前提であり、本ハーネスの範囲外。
#
# また `Wrapper.reset!` を呼ぶ spec は購読者を全消去して観測 writer を外すため、
# reset! しない安全な spec のみを対象に走らせること(`docs/self-observation.md`)。

require "ethotrace/rspec"
require "ethotrace/cli"
require "ethotrace/mcp"

module Ethotrace
  module Dogfood
    # 各 gem の「観測しても安全な」公開面。対象クラスがそのスイートで呼ばれ
    # なければ素通りするだけなので、3 gem 分をまとめて宣言してよい。
    SAFE_TARGETS = [
      # --- core: オフラインのデータ処理層(観測セッション自身は使わない) ---
      Ethotrace::Merge,
      Ethotrace::CLI::Reader,
      Ethotrace::CLI::Aggregator,
      Ethotrace::CLI::Renderer,
      Ethotrace::CLI::Color,
      Ethotrace::CLI::MergeCommand,
      Ethotrace::CLI::ViewCommand,
      # --- ethotrace-mcp: MCP 非依存の純クエリ層 + 薄い配線 ---
      Ethotrace::MCP::Catalog,
      Ethotrace::MCP::Server,
      Ethotrace::MCP::Tools,
      Ethotrace::MCP::Stdio,
      Ethotrace::MCP::CLI,
      # --- ethotrace-rspec: 設定の純変換層 ---
      Ethotrace::RSpec::Configuration
    ].freeze
  end
end

Ethotrace::RSpec.setup do |config|
  config.output_dir = "tmp/dogfood"
  # 公開する成果物の差分を安定させるため、PID 由来の既定 session_id を
  # gem 単位の決定的な名前で上書きする(再現手順で gem ごとに渡す)。
  session = ENV.fetch("ETHOTRACE_DOGFOOD_SESSION", nil)
  config.session_id = session if session && !session.empty?
  # インスタンスメソッドとクラス/モジュール関数の双方を観測する。対象クラスが
  # 当該 kind のメソッドを持たなければ TargetAdapter が素通りするだけ。
  Ethotrace::Dogfood::SAFE_TARGETS.each do |klass|
    config.observe(klass, kind: :instance)
    config.observe(klass, kind: :singleton)
  end
end
