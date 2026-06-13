# frozen_string_literal: true

require "ethotrace/mcp"
require "json"

# サーバはトランスポート抜きに handle_json(JSON-RPC 1 往復)でテストする。
# ツールの中身は Catalog 任せなので、ここでは「ツールが公開され、引数が Catalog へ
# 正しく渡り、結果が JSON text として返る」配線を固定する。
RSpec.describe Ethotrace::MCP::Server do
  def observation(owner:, name:, kind: "instance", requirements: [], errors: [], params: [])
    {
      schema_version: 1,
      type: "method_observation",
      method: { owner: owner, name: name, kind: kind },
      site: { path: "lib/#{owner.downcase}.rb", line: 1 },
      params: params,
      return: { classes_seen: [] },
      errors: errors,
      requirements: requirements,
      samples: 1,
      session: "s1"
    }
  end

  let(:catalog) do
    Ethotrace::MCP::Catalog.new(
      [
        observation(owner: "Pure", name: "add"),
        observation(
          owner: "Clock", name: "now",
          requirements: [{ kind: "time.read", write: false, direct: true, from: nil, detail: {} }]
        ),
        observation(
          owner: "Config", name: "rate",
          errors: [{ class: "KeyError", origin: "direct", from: nil }]
        )
      ]
    )
  end

  let(:server) { described_class.build(catalog) }

  # JSON-RPC で 1 ツールを呼び、text コンテンツを JSON.parse して返す。
  def call_tool(name, arguments = {})
    request = { jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: name, arguments: arguments } }
    response = JSON.parse(server.handle_json(JSON.generate(request)), symbolize_names: true)
    raise "tool error: #{response[:error] || response.dig(:result, :content)}" if response.dig(:result, :isError)

    JSON.parse(response.dig(:result, :content, 0, :text), symbolize_names: true)
  end

  describe "tools/list" do
    it "publishes every catalog query as a tool" do
      request = { jsonrpc: "2.0", id: 1, method: "tools/list", params: {} }
      names = JSON.parse(server.handle_json(JSON.generate(request)), symbolize_names: true)
                  .dig(:result, :tools).map { |tool| tool[:name] }
      expect(names).to contain_exactly(
        "lookup_method", "list_methods", "pure_methods", "flaky_suspects",
        "requiring", "methods_raising", "exceptions_of", "param_protocol"
      )
    end
  end

  describe "lookup_method" do
    it "returns the observed record for a method" do
      result = call_tool("lookup_method", { owner: "Clock", name: "now" })
      expect(result[:method]).to include(owner: "Clock", name: "now", kind: "instance")
    end

    it "marks an unobserved method as not observed" do
      result = call_tool("lookup_method", { owner: "Clock", name: "missing" })
      expect(result).to include(observed: false)
    end
  end

  describe "pure_methods" do
    # 例外を投げても Requirements が空なら純粋(Error チャネルは純粋性に影響しない)。
    it "returns every method with no Requirements" do
      result = call_tool("pure_methods")
      expect(result.map { |r| r[:method][:owner] }).to contain_exactly("Pure", "Config")
    end
  end

  describe "flaky_suspects" do
    it "returns methods touching nondeterministic Requirements" do
      result = call_tool("flaky_suspects")
      expect(result.map { |r| r[:method][:owner] }).to contain_exactly("Clock")
    end
  end

  describe "methods_raising" do
    it "filters by exception class when given" do
      result = call_tool("methods_raising", { exception: "KeyError" })
      expect(result.map { |r| r[:method][:owner] }).to contain_exactly("Config")
    end
  end

  describe "exceptions_of" do
    it "lists the exception classes a method can escape" do
      result = call_tool("exceptions_of", { owner: "Config", name: "rate" })
      expect(result).to contain_exactly("KeyError")
    end
  end
end
