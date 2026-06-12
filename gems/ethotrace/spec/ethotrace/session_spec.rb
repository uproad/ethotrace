# frozen_string_literal: true

require "stringio"

RSpec.describe Ethotrace::Session do
  let(:io) { StringIO.new }

  before do
    Ethotrace::Wrapper.reset!
    Ethotrace::AdapterRegistry.reset!
    Ethotrace::Tracker.reset
  end

  after do
    Ethotrace::Adapters::Stdlib.disable
    Ethotrace::Wrapper.reset!
    Ethotrace::AdapterRegistry.reset!
    Ethotrace::Tracker.reset
  end

  def records
    io.string.each_line.map { |line| JSON.parse(line, symbolize_names: true) }
  end

  describe ".start / #finish" do
    it "writes a session record with the enabled adapters and merged options" do
      session = described_class.start(io, id: "test-session", options: { record_sql_source: true })
      session.finish

      session_record = records.first
      expect(session_record).to include(type: "session", session: "test-session")
      expect(session_record[:adapters]).to eq(["stdlib"])
      expect(session_record[:options]).to include(trace_c_call: false, record_sql_source: true)
    end

    it "installs and uninstalls the probe through the given isolation strategy" do
      # 既定以外の戦略を渡すと、probe の設置/解除がその戦略経由で行われる。
      # 振る舞いは保つため、戦略は実 AdapterRegistry へ委譲しつつ呼び出しを記録する。
      isolation = Ethotrace::Isolation::Null.new
      allow(isolation).to receive(:install_probe).and_call_original
      allow(isolation).to receive(:uninstall_probe).and_call_original

      session = described_class.start(io, id: "iso", isolation: isolation)
      expect(isolation).to have_received(:install_probe).with(Ethotrace::AdapterRegistry)

      session.finish
      expect(isolation).to have_received(:uninstall_probe).with(Ethotrace::AdapterRegistry)
    end

    it "stops recording into the writer after finish (unsubscribed)" do
      session = described_class.start(io, id: "s")
      session.finish
      before = io.string.dup
      # finish 後に観測が走っても、購読解除済みなので書き込まれない。
      klass = Class.new { def m = 1 }
      Ethotrace::Wrapper.wrap(klass, :m)
      klass.new.m
      expect(io.string).to eq(before)
    end
  end

  describe "end-to-end pipeline" do
    around do |example|
      ENV["TAX_RATE"] = "8"
      example.run
    ensure
      ENV.delete("TAX_RATE")
    end

    it "records the three channels for an instrumented method through a real session" do
      session = described_class.start(io, id: "e2e")

      klass = Class.new do
        def rate = Integer(ENV.fetch("TAX_RATE"))
      end
      Ethotrace::Wrapper.wrap(klass, :rate)
      expect(klass.new.rate).to eq(8) # 透過(挙動は変わらない)

      session.finish

      observation = records.find { |r| r[:type] == "method_observation" }
      expect(observation[:method][:name]).to eq("rate")
      expect(observation[:return][:classes_seen]).to eq(["Integer"])
      expect(observation[:requirements].map { |r| r[:kind] }).to include("env.read")
    end

    it "never writes the ENV value (only the key) into the output" do
      session = described_class.start(io, id: "e2e")
      klass = Class.new { def rate = ENV.fetch("TAX_RATE") }
      Ethotrace::Wrapper.wrap(klass, :rate)
      klass.new.rate
      session.finish

      expect(io.string).not_to include("\"8\"")
      expect(io.string).to include("TAX_RATE")
    end

    it "observes the argument protocol of an instrumented method" do
      session = described_class.start(io, id: "e2e")

      # 引数役: Ruby 定義メソッドを持つ(:c_call なしで観測できる)。
      counter = Class.new { def tally = 1 }
      klass = Class.new do
        define_method(:run) { |item| item.tally }
      end
      Ethotrace::Wrapper.wrap(klass, :run)
      klass.new.run(counter.new)

      session.finish

      observation = records.find { |r| r[:type] == "method_observation" && r[:method][:name] == "run" }
      slot = observation[:params].first
      expect(slot).to include(position: 0, name: "item")
      expect(slot[:protocol]).to include(a_hash_including(name: "tally"))
    end

    it "observes C-method protocol only when trace_c_call is opted in" do
      session = described_class.start(io, id: "e2e", options: { trace_c_call: true })
      klass = Class.new do
        define_method(:run) { |text| text.upcase }
      end
      Ethotrace::Wrapper.wrap(klass, :run)
      klass.new.run(+"hi")

      session.finish

      observation = records.find { |r| r[:type] == "method_observation" && r[:method][:name] == "run" }
      slot = observation[:params].first
      expect(slot[:protocol].map { |e| e[:name] }).to include("upcase")
    end
  end
end
