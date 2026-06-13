# frozen_string_literal: true

require "stringio"
require "tmpdir"

RSpec.describe Ethotrace::JSONLWriter do
  let(:io) { StringIO.new }
  let(:fixed_time) { Time.new(2026, 6, 11, 12, 0, 0, "+09:00") }

  def build_writer(**overrides)
    described_class.new(
      io,
      session: "ethotrace-test",
      adapters: ["stdlib"],
      ruby_version: "3.4.1",
      ethotrace_version: "0.0.1",
      clock: -> { fixed_time },
      **overrides
    )
  end

  def lines
    io.string.each_line.map { |line| JSON.parse(line, symbolize_names: true) }
  end

  describe "the session record" do
    it "is written once on construction as the first line" do
      build_writer
      expect(lines.size).to eq(1)
      expect(lines.first).to eq(
        schema_version: 1,
        type: "session",
        session: "ethotrace-test",
        started_at: "2026-06-11T12:00:00+09:00",
        ruby_version: "3.4.1",
        ethotrace_version: "0.0.1",
        adapters: ["stdlib"],
        options: { trace_c_call: false, record_sql_source: false }
      )
    end

    it "merges given options over the defaults" do
      build_writer(options: { record_sql_source: true })
      expect(lines.first[:options]).to eq(trace_c_call: false, record_sql_source: true)
    end
  end

  describe "#call" do
    it "appends a method_observation record augmented with session and captured_at" do
      writer = build_writer
      ctx = Ethotrace::CallContext.new(owner: "Order", name: :total, kind: :instance, site: nil)
      ctx.record_return(1)
      writer.call(ctx)

      observation = lines.last
      expect(observation[:type]).to eq("method_observation")
      expect(observation[:method]).to eq(owner: "Order", name: "total", kind: "instance")
      expect(observation[:session]).to eq("ethotrace-test")
      expect(observation[:captured_at]).to eq("2026-06-11T12:00:00+09:00")
    end

    it "emits one valid JSON object per line" do
      writer = build_writer
      2.times do
        ctx = Ethotrace::CallContext.new(owner: "X", name: :m, kind: :instance, site: nil)
        writer.call(ctx)
      end
      # 全行が JSON としてパースでき、session 1 行 + observation 2 行。
      expect { lines }.not_to raise_error
      expect(lines.map { |record| record[:type] }).to eq(%w[session method_observation method_observation])
    end
  end

  describe "golden file" do
    let(:golden) do
      File.read(File.expand_path("../fixtures/observations.golden.jsonl", __dir__))
    end

    it "reproduces the committed golden output byte-for-byte" do
      writer = build_writer

      c1 = Ethotrace::CallContext.new(owner: "Order", name: :total_price, kind: :instance,
                                      site: { path: "app/models/order.rb", line: 12 })
      c1.record_argument(0, [1, 2, 3], name: :items)
      c1.record_protocol_call(0, :each, arity: 0, block: true)
      c1.record_protocol_call(0, :size, arity: 0, block: false)
      c1.record_return(100)
      c1.record_escaped_exception(KeyError.new, origin: "inherited", from: "Hash#fetch")
      writer.call(c1)

      c2 = Ethotrace::CallContext.new(owner: "Order", name: :create, kind: :singleton, site: nil)
      c2.record_return("ok")
      writer.call(c2)

      expect(io.string).to eq(golden)
    end
  end

  describe ".open" do
    it "writes to a file and closes it after the block" do
      dir = Dir.mktmpdir
      path = File.join(dir, "nested", "session.jsonl")
      writer = nil
      described_class.open(path, session: "file-test", clock: -> { fixed_time }) do |w|
        writer = w
        ctx = Ethotrace::CallContext.new(owner: "Y", name: :go, kind: :instance, site: nil)
        w.call(ctx)
      end

      records = File.readlines(path).map { |line| JSON.parse(line, symbolize_names: true) }
      expect(records.map { |r| r[:type] }).to eq(%w[session method_observation])
      expect(writer).to be_closed
    ensure
      FileUtils.remove_entry(dir) if dir
    end
  end

  describe "#close" do
    it "is safe to call more than once" do
      writer = build_writer
      writer.close
      expect { writer.close }.not_to raise_error
    end
  end

  describe "as a Collector subscriber (end-to-end)" do
    before do
      Ethotrace::Wrapper.reset!
      Ethotrace::Collector.reset!
    end

    after do
      Ethotrace::Wrapper.reset!
      Ethotrace::Collector.reset!
      Ethotrace::Tracker.reset
    end

    it "records observations for instrumented calls" do
      writer = build_writer
      Ethotrace::Collector.subscribe(writer)

      klass = Class.new { def double(num) = num * 2 }
      Ethotrace::Wrapper.wrap(klass, :double)
      expect(klass.new.double(21)).to eq(42)

      observation = lines.last
      expect(observation[:type]).to eq("method_observation")
      expect(observation[:method][:name]).to eq("double")
      expect(observation[:return][:classes_seen]).to eq(["Integer"])
    end
  end
end
