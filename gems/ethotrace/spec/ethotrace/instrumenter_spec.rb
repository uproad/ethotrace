# frozen_string_literal: true

RSpec.describe Ethotrace::Instrumenter do
  subject(:instrumenter) { described_class.new }

  before { Ethotrace::Wrapper.reset! }

  after { Ethotrace::Wrapper.reset! }

  describe "#wrap_method" do
    it "installs an observation wrapper via the core Wrapper" do
      klass = Class.new { def total = 0 }
      expect(instrumenter.wrap_method(klass, :total)).to be(true)
      expect(Ethotrace::Wrapper.instrumented?(klass, :total)).to be(true)
    end

    it "wraps singleton methods when kind: :singleton is given" do
      klass = Class.new { def self.build = :ok }
      instrumenter.wrap_method(klass, :build, kind: :singleton)
      expect(Ethotrace::Wrapper.instrumented?(klass, :build, kind: :singleton)).to be(true)
    end

    it "reports false on a second wrap of the same method (no double wrap)" do
      klass = Class.new { def total = 0 }
      instrumenter.wrap_method(klass, :total)
      expect(instrumenter.wrap_method(klass, :total)).to be(false)
    end
  end
end
