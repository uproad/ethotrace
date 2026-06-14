# frozen_string_literal: true

require "ethotrace/mcp"
require "json"
require "stringio"
require "tmpdir"

RSpec.describe Ethotrace::MCP::CLI do
  def observation(owner:, name:)
    {
      schema_version: 1, type: "method_observation",
      method: { owner: owner, name: name, kind: "instance" },
      site: nil, params: [], return: { classes_seen: [] },
      errors: [], requirements: [], samples: 1, session: "s1"
    }
  end

  def rpc(method, params = {})
    "#{JSON.generate(jsonrpc: "2.0", id: 1, method: method, params: params)}\n"
  end

  it "prints usage to err and exits 0 on --help without starting a server" do
    err = StringIO.new
    status = described_class.start(["--help"], input: StringIO.new, output: StringIO.new, err: err)
    expect(status).to eq(0)
    expect(err.string).to include("Usage: ethotrace-mcp")
  end

  it "loads the given observations and serves them over stdio" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "observations.jsonl")
      File.write(path, JSON.generate(observation(owner: "Order", name: "total")))
      output = StringIO.new

      status = described_class.start(
        [path], input: StringIO.new(rpc("tools/call", { name: "list_methods", arguments: {} })),
                output: output, err: StringIO.new
      )

      expect(status).to eq(0)
      payload = JSON.parse(output.string, symbolize_names: true)
      methods = JSON.parse(payload.dig(:result, :content, 0, :text), symbolize_names: true)
      expect(methods.first[:method]).to include(owner: "Order", name: "total")
    end
  end

  it "keeps stdout free of loader warnings (JSON-RPC 専用)" do
    err = StringIO.new
    output = StringIO.new

    described_class.start(
      ["no-such-file.jsonl"], input: StringIO.new(rpc("tools/list")),
                              output: output, err: err
    )

    expect(err.string).to include("no such file")
    # stdout は妥当な JSON-RPC のみ(警告が混ざらない)。
    expect { JSON.parse(output.string) }.not_to raise_error
  end
end
