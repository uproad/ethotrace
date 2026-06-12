# frozen_string_literal: true

require "ethotrace/rspec"

RSpec.describe Ethotrace::RSpec::Configuration do
  subject(:config) { described_class.new }

  it "defaults output_dir to tmp/ethotrace and starts with no targets" do
    expect(config.output_dir).to eq("tmp/ethotrace")
    expect(config.targets).to be_empty
    expect(config.options).to eq({})
  end

  describe "#observe" do
    it "accumulates targets and returns self for chaining" do
      result = config.observe(String, methods: %i[upcase]).observe(Integer, kind: :singleton)
      expect(result).to be(config)
      expect(config.targets.map(&:klass)).to eq([String, Integer])
      expect(config.targets.map(&:kind)).to eq(%i[instance singleton])
    end
  end

  describe "#session_id" do
    around do |example|
      saved = ENV.fetch("TEST_ENV_NUMBER", nil)
      example.run
      ENV["TEST_ENV_NUMBER"] = saved
    end

    it "derives from the PID for a single (non-parallel) run" do
      ENV.delete("TEST_ENV_NUMBER")
      expect(config.session_id).to eq("rspec-pid#{Process.pid}")
    end

    it "includes the parallel worker number when TEST_ENV_NUMBER is set" do
      ENV["TEST_ENV_NUMBER"] = "2"
      expect(config.session_id).to eq("rspec-w2-pid#{Process.pid}")
    end

    it "honors an explicit session_id" do
      config.session_id = "custom"
      expect(config.session_id).to eq("custom")
    end
  end

  describe "#output_path" do
    it "joins output_dir and session_id with a .jsonl extension" do
      config.output_dir = "out"
      config.session_id = "w1"
      expect(config.output_path).to eq("out/w1.jsonl")
    end
  end

  describe "#adapters" do
    it "always includes the stdlib adapter" do
      expect(config.adapters.map(&:name)).to eq(["stdlib"])
    end

    it "adds a target adapter when targets are present" do
      config.observe(String)
      expect(config.adapters.map(&:name)).to eq(%w[stdlib rspec-targets])
    end
  end
end
