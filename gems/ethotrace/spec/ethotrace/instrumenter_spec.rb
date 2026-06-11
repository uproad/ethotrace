# frozen_string_literal: true

RSpec.describe Ethotrace::Instrumenter do
  subject(:instrumenter) { described_class.new }

  before { Ethotrace::Wrapper.reset! }

  after do
    Ethotrace::Wrapper.reset!
    Ethotrace::Tracker.reset
  end

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

  describe "#record_effect" do
    it "attributes the effect to the active call stack" do
      ctx = Ethotrace::Tracker.begin_call(owner: "A", name: :a, kind: :instance)
      instrumenter.record_effect("env.read", write: false, key: "HOME")
      expect(ctx.to_observation[:requirements].first)
        .to include(kind: "env.read", direct: true, detail: { key: "HOME" })
    end

    it "is suppressed under the re-entry guard (no self-recording)" do
      ctx = Ethotrace::Tracker.begin_call(owner: "A", name: :a, kind: :instance)
      # トレーサ内部にいる間(in_tracer)は記録しない。
      Ethotrace::ReentryGuard.guard do
        instrumenter.record_effect("time.read", write: false)
      end
      expect(ctx.to_observation[:requirements]).to be_empty
    end
  end
end
