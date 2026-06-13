# frozen_string_literal: true

require "ethotrace"
require_relative "mcp/version"
require_relative "mcp/catalog"
require_relative "mcp/tools"
require_relative "mcp/server"

module Ethotrace
  # 自己観測データ(`observations.jsonl`)を MCP サーバとして公開するデータ消費者。
  #
  # core(観測プロセス)とは完全に分離する: 本 gem は計装を一切ロードせず、
  # schema_version 付き JSONL を読むだけの消費側に徹する(設計資料 §3 / §9、
  # `docs/schema.md`)。第一のユーザーは Ethotrace を開発する Claude Code 自身で、
  # 「このメソッドは何を要求/返却し、どんな例外・Requirements を持つか」を MCP
  # クエリで参照しながら開発を進めるブートストラップループの起点になる。
  module MCP
    # ethotrace-mcp 固有のエラーの基底クラス。
    class Error < ::Ethotrace::Error; end
  end
end
