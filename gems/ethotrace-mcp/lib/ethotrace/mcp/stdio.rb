# frozen_string_literal: true

module Ethotrace
  module MCP
    # `::MCP::Server` を stdio 上の JSON-RPC で駆動する最小トランスポート。
    #
    # 1 行 = 1 JSON-RPC メッセージ(改行区切り)を入力から読み、`handle_json` で処理し、
    # 応答を出力へ 1 行ずつ書く。通知(id 無し)は `handle_json` が nil を返すため何も
    # 書かない。MCP は stdout を**プロトコル専用**チャネルにするので、警告・ログは
    # 一切 stdout に出さない(Reader の警告は stderr。`Catalog.load` 既定)。
    module Stdio
      # @param server [::MCP::Server]
      # @param input [IO] JSON-RPC 入力(既定 $stdin)。
      # @param output [IO] JSON-RPC 出力(既定 $stdout)。
      def self.run(server, input: $stdin, output: $stdout)
        input.each_line do |line|
          line = line.strip
          next if line.empty?

          response = server.handle_json(line)
          next if response.nil? || response.empty?

          output.puts(response)
          output.flush
        end
      end
    end
  end
end
