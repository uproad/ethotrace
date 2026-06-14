# frozen_string_literal: true

require "json"
require "mcp"
require_relative "tools"

module Ethotrace
  module MCP
    # {Catalog} のクエリを MCP プロトコル(JSON-RPC)で公開するサーバを組み立てる。
    #
    # トランスポート(stdio など)からは独立しており、`build` が返す `::MCP::Server`
    # は `handle_json(request)` で 1 リクエストずつ処理できる。実際の stdio ループは
    # `exe/ethotrace-mcp` が回す。これにより、サーバのツール挙動は JSON 入力 → JSON
    # 出力としてプロトコル抜きにテストできる。
    #
    # MCP プロトコルの SDK は `::MCP`(`Ethotrace::MCP` の内側では `MCP` は自分自身を
    # 指すため、常に先頭 `::` で参照する)。
    module Server
      INSTRUCTIONS = <<~TEXT
        Ethotrace の観測結果(observed contract)を提供する。各メソッドについて
        「引数に要求するプロトコル・戻り値クラス・エスケープ例外・Requirements
        (外部接触)」を返す。返る規約はテストで実行されたパスの下限であり、
        未実行パスは含まれない。
      TEXT

      # @param catalog [Catalog] 公開する観測データ。
      # @param name [String] サーバ名。
      # @param version [String] サーババージョン。
      # @return [::MCP::Server]
      def self.build(catalog, name: "ethotrace", version: VERSION)
        server = ::MCP::Server.new(name: name, version: version, instructions: INSTRUCTIONS)
        Tools.install(server, catalog)
        server
      end
    end
  end
end
