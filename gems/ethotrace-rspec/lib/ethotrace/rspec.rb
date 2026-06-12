# frozen_string_literal: true

require "ethotrace"
require_relative "rspec/version"

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
  module RSpec
    # ethotrace-rspec 固有のエラーの基底クラス。
    class Error < ::Ethotrace::Error; end
  end
end
