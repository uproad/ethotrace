# frozen_string_literal: true

require "ethotrace/mcp"

RSpec.describe Ethotrace::MCP do
  it "has a version number" do
    expect(Ethotrace::MCP::VERSION).not_to be_nil
  end

  it "defines its own error rooted in the core Error" do
    expect(Ethotrace::MCP::Error.ancestors).to include(Ethotrace::Error)
  end
end
