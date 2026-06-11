# frozen_string_literal: true

require "securerandom"

RSpec.describe Ethotrace::Adapters::Stdlib do
  subject(:adapter) { described_class.new }

  let(:instrumenter) { Ethotrace::Instrumenter.new }

  before { adapter.install(instrumenter) }

  after do
    adapter.uninstall(instrumenter)
    Ethotrace::Tracker.reset
  end

  # 観測中メソッドを模して context を積み、ブロック実行中に記録された
  # requirements を返す。
  def requirements_during
    context = Ethotrace::Tracker.begin_call(owner: "Caller", name: :run, kind: :instance)
    yield
    context.to_observation[:requirements]
  ensure
    Ethotrace::Tracker.end_call(context)
  end

  describe "#name" do
    it "is the short token for the session record" do
      expect(adapter.name).to eq("stdlib")
    end
  end

  describe "env.read" do
    around do |example|
      ENV["ETHOTRACE_TEST"] = "secret-value"
      example.run
    ensure
      ENV.delete("ETHOTRACE_TEST")
    end

    it "records ENV#[] with the key only (never the value)" do
      # ENV#[] フックそのものを検証するため、あえて ENV.fetch ではなく [] を使う。
      reqs = requirements_during { ENV["ETHOTRACE_TEST"] } # rubocop:disable Style/FetchEnvVar
      expect(reqs).to eq([{ kind: "env.read", write: false, direct: true, from: nil,
                            detail: { key: "ETHOTRACE_TEST" } }])
    end

    it "does not leak the ENV value into detail" do
      reqs = requirements_during { ENV["ETHOTRACE_TEST"] } # rubocop:disable Style/FetchEnvVar
      expect(reqs.first[:detail].values).not_to include("secret-value")
    end

    it "records ENV#fetch and stays transparent (returns the real value)" do
      value = nil
      reqs = requirements_during { value = ENV.fetch("ETHOTRACE_TEST") }
      expect(value).to eq("secret-value")
      expect(reqs.first).to include(kind: "env.read", detail: { key: "ETHOTRACE_TEST" })
    end
  end

  describe "time.read" do
    it "records Time.now and returns a real Time" do
      result = nil
      reqs = requirements_during { result = Time.now }
      expect(result).to be_a(Time)
      expect(reqs.first).to include(kind: "time.read", write: false)
    end

    it "records Process.clock_gettime" do
      reqs = requirements_during { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
      expect(reqs.map { |r| r[:kind] }).to include("time.read")
    end
  end

  describe "random.read" do
    it "records SecureRandom and returns a real value" do
      hex = nil
      reqs = requirements_during { hex = SecureRandom.hex(4) }
      expect(hex).to match(/\A[0-9a-f]{8}\z/)
      expect(reqs.map { |r| r[:kind] }).to include("random.read")
    end

    it "records Random.rand" do
      reqs = requirements_during { Random.rand(10) }
      expect(reqs.map { |r| r[:kind] }).to include("random.read")
    end
  end

  describe "attribution across the call stack" do
    it "marks the deepest frame direct and the caller inherited" do
      outer = Ethotrace::Tracker.begin_call(owner: "A", name: :a, kind: :instance)
      inner = Ethotrace::Tracker.begin_call(owner: "B", name: :b, kind: :instance)
      Time.now
      expect(inner.to_observation[:requirements].first).to include(direct: true, from: nil)
      expect(outer.to_observation[:requirements].first).to include(direct: false, from: "B#b")
    ensure
      Ethotrace::Tracker.end_call(inner)
      Ethotrace::Tracker.end_call(outer)
    end
  end

  describe "uninstall / re-entry guard" do
    it "records nothing after uninstall" do
      adapter.uninstall(instrumenter)
      reqs = requirements_during { Time.now }
      expect(reqs).to be_empty
    end

    it "records nothing while inside the tracer (re-entry guard)" do
      reqs = requirements_during do
        Ethotrace::ReentryGuard.guard { Time.now }
      end
      expect(reqs).to be_empty
    end
  end
end
