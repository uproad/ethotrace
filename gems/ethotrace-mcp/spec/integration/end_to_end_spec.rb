# frozen_string_literal: true

require "ethotrace/mcp"
require "json"
require "stringio"
require "tmpdir"

# 観測 JSONL ファイル → Catalog → Server → Stdio(JSON-RPC)の全経路を、MCP
# クライアントの 1 セッション(initialize → tools/call)として通しで固定する。
# 個々のクエリは Catalog/Server spec で固定済みなので、ここは「実ファイルから
# 起動して規約が JSON-RPC で返る」配線そのものを検証する。
RSpec.describe "ethotrace-mcp end-to-end", type: :integration do
  # 2 ワーカー分の生ログ(同一メソッドの別観測)。マージされて 1 規約になる。
  let(:raw_log) do
    [
      {
        schema_version: 1, type: "session", session: "w1",
        started_at: "2026-06-13T00:00:00+09:00", ruby_version: "4.0.3",
        ethotrace_version: "0.1.0", adapters: ["stdlib"], options: {}
      },
      {
        schema_version: 1, type: "method_observation",
        method: { owner: "Cart", name: "total", kind: "instance" },
        site: { path: "lib/cart.rb", line: 4 },
        params: [
          { position: 0, name: "items", protocol: [{ name: "sum", arity: 0, block: true }], classes_seen: ["Array"] }
        ],
        return: { classes_seen: ["Integer"] },
        errors: [],
        requirements: [{ kind: "env.read", write: false, direct: true, from: nil, detail: { key: "TAX" } }],
        samples: 3, session: "w1"
      },
      {
        schema_version: 1, type: "method_observation",
        method: { owner: "Cart", name: "total", kind: "instance" },
        site: { path: "lib/cart.rb", line: 4 },
        params: [], return: { classes_seen: ["Float"] },
        errors: [{ class: "KeyError", origin: "inherited", from: "Hash#fetch" }],
        requirements: [], samples: 2, session: "w2"
      }
    ]
  end

  def session(input_lines)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "observations.jsonl")
      File.write(path, raw_log.map { |record| JSON.generate(record) }.join("\n"))
      output = StringIO.new
      Ethotrace::MCP::CLI.start(
        [path], input: StringIO.new(input_lines.join("\n")), output: output, err: StringIO.new
      )
      output.string.each_line.map { |line| JSON.parse(line, symbolize_names: true) }
    end
  end

  def rpc(id, method, params)
    JSON.generate(jsonrpc: "2.0", id: id, method: method, params: params)
  end

  def tool_payload(response)
    JSON.parse(response.dig(:result, :content, 0, :text), symbolize_names: true)
  end

  it "initializes then answers a lookup with the merged observed contract" do
    init = rpc(1, "initialize",
               { protocolVersion: "2024-11-05", capabilities: {}, clientInfo: { name: "spec", version: "0" } })
    lookup = rpc(2, "tools/call", { name: "lookup_method", arguments: { owner: "Cart", name: "total" } })

    responses = session([init, lookup])

    # initialize 応答にサーバ名が乗る。
    expect(responses.first.dig(:result, :serverInfo, :name)).to eq("ethotrace")

    record = tool_payload(responses.last)
    # 2 観測がマージされ、戻り値クラス・例外・Requirements が和集合で返る。
    expect(record[:return][:classes_seen]).to contain_exactly("Integer", "Float")
    expect(record[:errors].map { |error| error[:class] }).to contain_exactly("KeyError")
    expect(record[:requirements].map { |requirement| requirement[:kind] }).to contain_exactly("env.read")
    expect(record[:samples]).to eq(5)
  end

  it "answers a flaky/effect query across the merged store" do
    requiring = rpc(3, "tools/call", { name: "requiring", arguments: { kind: "env.read" } })

    record = tool_payload(session([requiring]).last)

    expect(record.map { |entry| entry[:method][:name] }).to contain_exactly("total")
  end
end
