# frozen_string_literal: true

require "ethotrace"
require_relative "target_adapter"

module Ethotrace
  module RSpec
    # ethotrace-rspec の観測設定。`Ethotrace::RSpec.setup` のブロックで構成する。
    #
    # 観測対象(どのクラスのどのメソッドを観測するか)・出力先ディレクトリ・
    # セッション ID・観測オプションを保持し、core の {Ethotrace::Session} を
    # 起動するための adapters / 出力パスへ翻訳する。
    class Configuration
      # 観測結果 JSONL の出力先ディレクトリ(既定: tmp/ethotrace)。
      attr_accessor :output_dir

      # 観測オプション(trace_c_call / record_sql_source 等。schema §3 の options)。
      attr_reader :options

      # 観測対象({Target} の配列)。
      attr_reader :targets

      def initialize
        @output_dir = "tmp/ethotrace"
        @options = {}
        @targets = []
        @session_id = nil
      end

      # 観測対象を追加する。
      #
      # @param klass [Module] 観測するクラス/モジュール。
      # @param methods [Array<Symbol>, nil] 観測するメソッド名。nil なら当該 kind の
      #   「klass 自身に定義された」メソッド全部(継承分は含めない)。
      # @param kind [Symbol] :instance / :singleton。
      def observe(klass, methods: nil, kind: :instance)
        @targets << Target.new(klass: klass, method_names: methods, kind: kind)
        self
      end

      # セッション ID。並列ワーカーごとに一意化する。明示設定がなければ
      # parallel_tests の TEST_ENV_NUMBER と PID から導出する
      # (例: "rspec-w2-pid4242" / 単一実行なら "rspec-pid4242")。
      def session_id
        @session_id ||= default_session_id
      end

      # セッション ID を明示設定する。
      attr_writer :session_id

      # 観測結果 JSONL の出力パス(<output_dir>/<session_id>.jsonl)。
      def output_path
        File.join(@output_dir, "#{session_id}.jsonl")
      end

      # core の {Ethotrace::Session} へ渡すアダプタ列。stdlib(Requirements 観測)に
      # 加え、観測対象があれば {TargetAdapter} を足す。
      def adapters
        adapters = [Ethotrace::Adapters::Stdlib.new]
        adapters << TargetAdapter.new(@targets) unless @targets.empty?
        adapters
      end

      private

      def default_session_id
        worker = ENV.fetch("TEST_ENV_NUMBER", nil)
        prefix = worker.nil? || worker.empty? ? "rspec" : "rspec-w#{worker}"
        "#{prefix}-pid#{Process.pid}"
      end
    end
  end
end
