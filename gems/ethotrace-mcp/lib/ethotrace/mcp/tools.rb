# frozen_string_literal: true

require "json"
require "mcp"

module Ethotrace
  module MCP
    # {Catalog} の各クエリを 1 つの MCP ツールとして `::MCP::Server` に登録する。
    #
    # ツールの戻り値は観測データ(JSONL スキーマそのままの Hash/配列)を JSON 文字列に
    # した text コンテンツ。observed contract である点(未実行パスは含まれない)を踏まえ、
    # 該当が無い場合は空配列や not-observed の注記を返す。メソッド指定は `kind`
    # ("instance" 既定 / "singleton")で曖昧さを解く。
    #
    # `::MCP::Server#define_tool` のブロックは tool 引数 + `server_context:` を**キーワード
    # 引数**として、かつツール側の文脈で `instance_exec` 実行する(ブロック内の `self` は
    # Tools ではない)。そのため各ブロックは `|**args|` で受け、ヘルパは `Tools.` 修飾で
    # 呼ぶ。定数はレキシカルに解決されるため修飾不要。
    module Tools
      # 「instance / singleton」を選ぶ共通スキーマ片。
      KIND_SCHEMA = { type: "string", enum: %w[instance singleton], default: "instance" }.freeze

      # owner+name+kind でメソッドを 1 つ特定するツールの入力スキーマ。
      METHOD_SCHEMA = {
        type: "object",
        properties: {
          owner: { type: "string", description: "定義クラス/モジュールの完全修飾名" },
          name: { type: "string", description: "メソッド名" },
          kind: KIND_SCHEMA
        },
        required: %w[owner name]
      }.freeze

      # すべてのツールをサーバへ登録する。
      # @param server [::MCP::Server]
      # @param catalog [Catalog]
      def self.install(server, catalog)
        lookup_method(server, catalog)
        list_methods(server, catalog)
        pure_methods(server, catalog)
        flaky_suspects(server, catalog)
        requiring(server, catalog)
        methods_raising(server, catalog)
        exceptions_of(server, catalog)
        param_protocol(server, catalog)
      end

      def self.lookup_method(server, catalog)
        server.define_tool(
          name: "lookup_method",
          description: "1 メソッドの観測規約(プロトコル・戻り値・例外・Requirements)を返す。",
          input_schema: METHOD_SCHEMA
        ) do |**args|
          method = Tools.method_args(args)
          Tools.respond(catalog.lookup(**method) || { observed: false, method: method })
        end
      end

      def self.list_methods(server, catalog)
        server.define_tool(
          name: "list_methods",
          description: "観測された全メソッドの規約レコードを返す。",
          input_schema: { type: "object", properties: {} }
        ) do |**_args|
          Tools.respond(catalog.methods)
        end
      end

      def self.pure_methods(server, catalog)
        server.define_tool(
          name: "pure_methods",
          description: "Requirements が空(R=∅ = 純粋の容疑)のメソッド一覧を返す。",
          input_schema: { type: "object", properties: {} }
        ) do |**_args|
          Tools.respond(catalog.pure_methods)
        end
      end

      def self.flaky_suspects(server, catalog)
        server.define_tool(
          name: "flaky_suspects",
          description: "非決定性 Requirements(既定 time.read / random.read)に接触する flaky 容疑メソッドを返す。",
          input_schema: {
            type: "object",
            properties: {
              kinds: {
                type: "array",
                items: { type: "string" },
                description: "flaky とみなす Requirements 語彙。省略時は time.read / random.read。"
              }
            }
          }
        ) do |**args|
          kinds = Array(args[:kinds])
          Tools.respond(kinds.empty? ? catalog.flaky_suspects : catalog.flaky_suspects(kinds: kinds))
        end
      end

      def self.requiring(server, catalog)
        server.define_tool(
          name: "requiring",
          description: "特定のエフェクト語彙(例: db.query / env.read / http.request)に接触するメソッドを返す。",
          input_schema: {
            type: "object",
            properties: { kind: { type: "string", description: "Requirements の語彙" } },
            required: %w[kind]
          }
        ) do |**args|
          Tools.respond(catalog.requiring(kind: args[:kind]))
        end
      end

      def self.methods_raising(server, catalog)
        server.define_tool(
          name: "methods_raising",
          description: "例外をエスケープさせうるメソッドを返す。exception 指定時はその例外を投げるものに絞る。",
          input_schema: {
            type: "object",
            properties: { exception: { type: "string", description: "絞り込む例外クラスの完全修飾名" } }
          }
        ) do |**args|
          Tools.respond(catalog.raisers(exception: args[:exception]))
        end
      end

      def self.exceptions_of(server, catalog)
        server.define_tool(
          name: "exceptions_of",
          description: "1 メソッドがエスケープさせうる例外クラス名の一覧を返す。",
          input_schema: METHOD_SCHEMA
        ) do |**args|
          method = Tools.method_args(args)
          classes = catalog.exceptions_of(**method)
          Tools.respond(classes.nil? ? { observed: false, method: method } : classes)
        end
      end

      def self.param_protocol(server, catalog)
        server.define_tool(
          name: "param_protocol",
          description: "1 メソッドの指定引数(position 起点 0)に観測されたプロトコルを返す。",
          input_schema: {
            type: "object",
            properties: {
              owner: { type: "string", description: "定義クラス/モジュールの完全修飾名" },
              name: { type: "string", description: "メソッド名" },
              position: { type: "integer", description: "引数位置(0 起点)" },
              kind: KIND_SCHEMA
            },
            required: %w[owner name position]
          }
        ) do |**args|
          protocol = catalog.param_protocol(**Tools.method_args(args), position: args[:position])
          Tools.respond(protocol.nil? ? { observed: false } : protocol)
        end
      end

      # ツール引数 Hash から owner/name/kind を取り出す(kind は既定 "instance")。
      # server_context など余分なキーは無視する。
      def self.method_args(args)
        { owner: args[:owner], name: args[:name], kind: args[:kind] || "instance" }
      end

      # 任意のデータを 1 つの text コンテンツ(整形 JSON)として返す。
      def self.respond(data)
        ::MCP::Tool::Response.new([{ type: "text", text: JSON.pretty_generate(data) }])
      end
    end
  end
end
