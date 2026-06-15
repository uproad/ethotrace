# frozen_string_literal: true

# Ethotrace 自身を Ethotrace で観測する dogfooding 注入ファイル。
#
# **各 gem の root から、その gem のスイートを観測する**ために RSpec の
# `-r`(--require)で読み込む。観測対象はその gem の「観測に関与しないオフラインの
# データ処理層・純クエリ層」のみ。観測エンジン本体(Wrapper/Tracker/Session/
# TracePoint 等)を観測するとラップ呼び出しが共有スタックや購読者をテスト中に変化
# させてエンジン自身の単体テストを壊し、自己言及で SystemStackError に至るため対象外
# (設計資料 §4.8 / CLAUDE.md ルール7)。また `Wrapper.reset!` を呼ぶ spec は購読者を
# 全消去して観測 writer を外すため、reset! しない安全な spec のみを対象に走らせる。
#
#   cd gems/<gem>
#   ETHOTRACE_DOGFOOD_SESSION=<core|mcp|rspec> \
#     bundle exec rspec -r ../../script/dogfood/observe.rb -I spec <safe specs>
#
# 観測対象プロジェクトのルート(= 各 gem の root = 実行時の作業ディレクトリ)が
# `Ethotrace.base_dir` になるため、`site.path` はその gem 相対(`lib/...`)で記録される。

require "ethotrace/rspec"

module Ethotrace
  # dogfooding 注入の補助。観測対象 gem を ETHOTRACE_DOGFOOD_SESSION で選び、その
  # gem のロード済み公開クラスだけを観測対象として解決する。
  module Dogfood
    # gem ごとの「観測しても安全な」公開面と、それを定義するエントリ require。
    # 対象は完全修飾名の文字列で持ち、ロード済みの定数だけを観測する(別 gem の
    # 定数は未ロードなので自然に除外される)。
    GEMS = {
      "core" => {
        require: "ethotrace/cli",
        targets: %w[
          Ethotrace::Merge
          Ethotrace::CLI::Reader
          Ethotrace::CLI::Aggregator
          Ethotrace::CLI::Renderer
          Ethotrace::CLI::Color
          Ethotrace::CLI::MergeCommand
          Ethotrace::CLI::ViewCommand
        ]
      },
      "mcp" => {
        require: "ethotrace/mcp",
        targets: %w[
          Ethotrace::MCP::Catalog
          Ethotrace::MCP::Server
          Ethotrace::MCP::Tools
          Ethotrace::MCP::Stdio
          Ethotrace::MCP::CLI
        ]
      },
      "rspec" => {
        require: "ethotrace/rspec",
        targets: %w[Ethotrace::RSpec::Configuration]
      }
    }.freeze

    module_function

    # ETHOTRACE_DOGFOOD_SESSION(= gem キー)から、ロード済みの観測対象クラスを返す。
    def targets
      key = ENV.fetch("ETHOTRACE_DOGFOOD_SESSION", nil)
      config = GEMS.fetch(key) { raise "ETHOTRACE_DOGFOOD_SESSION must be one of #{GEMS.keys.join(", ")}" }
      require config[:require]
      config[:targets].filter_map { |name| Object.const_get(name) if Object.const_defined?(name) }
    end
  end
end

Ethotrace::RSpec.setup do |config|
  # 生ログの出力先。各 gem の root を汚さないよう、駆動スクリプト(generate.sh)は
  # OS 一時ディレクトリを渡す。既定は gem 直下の tmp。
  config.output_dir = ENV.fetch("ETHOTRACE_DOGFOOD_OUT", "tmp/dogfood")
  # 公開する成果物の差分を安定させるため、PID 由来の既定 session_id を gem キーで上書き。
  config.session_id = ENV.fetch("ETHOTRACE_DOGFOOD_SESSION")

  # インスタンスメソッドとクラス/モジュール関数の双方を観測する。対象クラスが
  # 当該 kind のメソッドを持たなければ TargetAdapter が素通りするだけ。
  Ethotrace::Dogfood.targets.each do |klass|
    config.observe(klass, kind: :instance)
    config.observe(klass, kind: :singleton)
  end
end
