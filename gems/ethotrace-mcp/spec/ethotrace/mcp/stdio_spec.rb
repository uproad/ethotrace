# frozen_string_literal: true

require "ethotrace/mcp"
require "json"
require "stringio"

RSpec.describe Ethotrace::MCP::Stdio do
  let(:server) { Ethotrace::MCP::Server.build(Ethotrace::MCP::Catalog.new([])) }

  def rpc(id, method, params = {})
    "#{JSON.generate(jsonrpc: "2.0", id: id, method: method, params: params)}\n"
  end

  it "answers each JSON-RPC line with one response line" do
    input = StringIO.new(rpc(1, "tools/list"))
    output = StringIO.new

    described_class.run(server, input: input, output: output)

    lines = output.string.each_line.to_a
    expect(lines.size).to eq(1)
    expect(JSON.parse(lines.first, symbolize_names: true).dig(:result, :tools)).to be_an(Array)
  end

  it "writes nothing for a notification (id 無し → handle_json が nil)" do
    input = StringIO.new("#{JSON.generate(jsonrpc: "2.0", method: "notifications/initialized", params: {})}\n")
    output = StringIO.new

    described_class.run(server, input: input, output: output)

    expect(output.string).to be_empty
  end

  it "skips blank lines" do
    input = StringIO.new("\n  \n#{rpc(7, "tools/list")}")
    output = StringIO.new

    described_class.run(server, input: input, output: output)

    expect(output.string.each_line.to_a.size).to eq(1)
  end
end
