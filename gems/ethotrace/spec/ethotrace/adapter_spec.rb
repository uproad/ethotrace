# frozen_string_literal: true

RSpec.describe Ethotrace::Adapter do
  let(:instrumenter) { Ethotrace::Instrumenter.new }

  describe "the base lifecycle" do
    subject(:adapter) { described_class.new }

    it "treats every lifecycle hook as a no-op" do
      expect(adapter.install(instrumenter)).to be_nil
      expect(adapter.uninstall(instrumenter)).to be_nil
      expect(adapter.on_session_start("s1")).to be_nil
      expect(adapter.on_session_end("s1")).to be_nil
    end
  end

  describe "#name" do
    it "defaults to the class name" do
      stub_const("Ethotrace::Adapters::Demo", Class.new(described_class))
      expect(Ethotrace::Adapters::Demo.new.name).to eq("Ethotrace::Adapters::Demo")
    end

    it "can be overridden to a short token for the session record" do
      klass = Class.new(described_class) { def name = "stdlib" }
      expect(klass.new.name).to eq("stdlib")
    end
  end
end
