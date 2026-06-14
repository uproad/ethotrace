# frozen_string_literal: true

require_relative "catalog"
require_relative "server"
require_relative "stdio"

module Ethotrace
  module MCP
    # `exe/ethotrace-mcp` の実体。観測 JSONL を読み込み、MCP サーバを stdio で起動する。
    #
    # 引数は観測データのパス(複数可)。省略時はマージ済みの確定ストア
    # `ethotrace/observations.jsonl`(`docs/schema.md` の既定配置)を読む。stdout は
    # JSON-RPC 専用のため、使い方・警告は stderr へ出す。
    module CLI
      # 省略時に読むマージ済み観測ストア(リポジトリ相対)。
      DEFAULT_STORE = "ethotrace/observations.jsonl"

      USAGE = <<~TEXT.freeze
        Usage: ethotrace-mcp [observations.jsonl ...]

        Ethotrace の観測結果を MCP サーバ(stdio / JSON-RPC)として公開する。
        引数を省略すると #{DEFAULT_STORE} を読む。
      TEXT

      module_function

      # @param argv [Array<String>]
      # @param input [IO] JSON-RPC 入力。
      # @param output [IO] JSON-RPC 出力(stdout 専用)。
      # @param err [IO] 使い方・警告の出力先。
      # @return [Integer] 終了ステータス。
      def start(argv, input: $stdin, output: $stdout, err: $stderr)
        if argv.intersect?(%w[-h --help])
          err.puts(USAGE)
          return 0
        end

        paths = argv.empty? ? [DEFAULT_STORE] : argv
        catalog = Catalog.load(*paths, warn_io: err)
        Stdio.run(Server.build(catalog), input: input, output: output)
        0
      end
    end
  end
end
