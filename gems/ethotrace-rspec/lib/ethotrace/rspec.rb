# frozen_string_literal: true

require "ethotrace"
require_relative "rspec/version"
require_relative "rspec/configuration"
require_relative "rspec/target_adapter"
require_relative "rspec/session_runner"

module Ethotrace
  # RSpec ライフサイクルへの接続アダプタ。
  #
  # core(`Ethotrace::Session`)はテストフレームワークを知らない。この gem が
  # RSpec のスイート開始/終了に観測セッションを接続し、ワーカーごとに
  # `tmp/ethotrace/<session>.jsonl` を書き出す。意味論(計装対象の選択・
  # テストライフサイクル接続)はアダプタの責務であり、core は物理学に徹する。
  #
  # フレームワーク本体は定数衝突を避けるため常に `::RSpec` で参照する
  # (`Ethotrace::RSpec` 名前空間の内側では `RSpec` は自分自身を指すため)。
  #
  # 使い方(spec_helper.rb 等):
  #
  #   require "ethotrace/rspec"
  #
  #   Ethotrace::RSpec.setup do |config|
  #     config.observe Order              # Order の自前インスタンスメソッド全部
  #     config.observe Tax, methods: %i[rate]
  #   end
  #
  module RSpec
    # ethotrace-rspec 固有のエラーの基底クラス。
    class Error < ::Ethotrace::Error; end

    class << self
      # スイート全体で 1 つだけ走る観測セッション。before/after(:suite) 間で共有する。
      attr_accessor :session

      # RSpec のスイートライフサイクルへ観測セッションを接続する。
      #
      # `before(:suite)` でセッションを開始し、`after(:suite)` で終了する。観測
      # 対象や出力先はブロックで受け取る {Configuration} に設定する。
      #
      # @param rspec [#before, #after] フックを登録する先(既定: ::RSpec.configuration)。
      # @yieldparam config [Configuration]
      # @return [Configuration] 構成済みの設定。
      def setup(rspec: ::RSpec.configuration)
        config = Configuration.new
        yield config if block_given?
        rspec.before(:suite) { Ethotrace::RSpec.start(config) }
        rspec.after(:suite) { Ethotrace::RSpec.finish }
        config
      end

      # 観測セッションを開始する(before(:suite) フックの実体)。
      def start(config)
        self.session = SessionRunner.start(config)
      end

      # 観測セッションを終了する(after(:suite) フックの実体)。
      def finish
        SessionRunner.finish(session)
        self.session = nil
      end
    end
  end
end
