# frozen_string_literal: true

require "ethotrace"
require "fileutils"

module Ethotrace
  module RSpec
    # {Configuration} から core の {Ethotrace::Session} を起動・終了する。
    #
    # 出力先ファイル(<output_dir>/<session_id>.jsonl)を追記モードで開き、
    # session を起動する。並列ワーカーはワーカーごとに別ファイルへ書き、後で
    # `ethotrace merge` で統合する前提(docs/schema.md §6)。
    module SessionRunner
      module_function

      # 観測セッションを開始する。
      #
      # @param config [Configuration]
      # @return [Ethotrace::Session]
      def start(config)
        FileUtils.mkdir_p(File.dirname(config.output_path))
        # fd は session が寿命を通じて保持し、session#finish が閉じる。
        # そのためブロック形は使わない。
        io = File.open(config.output_path, "a") # rubocop:disable Style/FileOpen
        io.sync = true
        Ethotrace::Session.start(
          io,
          id: config.session_id,
          adapters: config.adapters,
          options: config.options
        )
      end

      # 観測セッションを終了する(io も session#finish が閉じる)。
      #
      # @param session [Ethotrace::Session, nil]
      def finish(session)
        session&.finish
      end
    end
  end
end
