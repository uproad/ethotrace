# frozen_string_literal: true

require "ethotrace/cli"

RSpec.describe Ethotrace::CLI do
  let(:out) { StringIO.new }
  let(:err) { StringIO.new }

  def start(*argv)
    described_class.start(argv, out: out, err: err)
  end

  it "prints the version with --version" do
    expect(start("--version")).to eq(0)
    expect(out.string.strip).to eq(Ethotrace::VERSION)
  end

  it "prints usage with no command" do
    expect(start).to eq(0)
    expect(out.string).to include("Usage: ethotrace")
    expect(out.string).to include("view")
  end

  it "prints usage with help" do
    expect(start("help")).to eq(0)
    expect(out.string).to include("Usage: ethotrace")
  end

  it "reports an unknown command and returns 1" do
    expect(start("frobnicate")).to eq(1)
    expect(err.string).to match(/unknown command: frobnicate/)
  end

  it "dispatches to the view command" do
    # 入力ファイルなしの view はステータス 1 を返す(委譲できている証跡)。
    expect(start("view")).to eq(1)
    expect(err.string).to match(/no input files/)
  end
end
