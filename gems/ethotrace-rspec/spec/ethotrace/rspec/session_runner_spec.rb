# frozen_string_literal: true

require "ethotrace/rspec"
require "tmpdir"
require "json"

# 観測対象のフィクスチャ。SessionRunner が実セッションで観測する。
class SessionRunnerFixture
  def shout(word)
    word.to_s.upcase
  end
end

RSpec.describe Ethotrace::RSpec::SessionRunner do
  around do |example|
    Dir.mktmpdir { |dir| @dir = dir and example.run }
  end

  def config_for(klass, **)
    Ethotrace::RSpec::Configuration.new.tap do |config|
      config.output_dir = @dir
      config.session_id = "test"
      config.observe(klass, **)
    end
  end

  def records
    File.readlines(File.join(@dir, "test.jsonl")).map { |line| JSON.parse(line, symbolize_names: true) }
  end

  it "writes a session record and observes calls to the configured target" do
    config = config_for(SessionRunnerFixture, methods: %i[shout])
    session = described_class.start(config)
    begin
      expect(SessionRunnerFixture.new.shout("hi")).to eq("HI") # 透過性: 戻り値は不変
    ensure
      described_class.finish(session)
    end

    types = records.map { |r| r[:type] }
    expect(types).to include("session", "method_observation")

    session_record = records.find { |r| r[:type] == "session" }
    expect(session_record[:session]).to eq("test")
    expect(session_record[:adapters]).to eq(%w[stdlib rspec-targets])

    observation = records.find { |r| r.dig(:method, :owner) == "SessionRunnerFixture" }
    expect(observation[:method]).to include(name: "shout", kind: "instance")
    expect(observation.dig(:return, :classes_seen)).to eq(["String"])
  end

  it "creates the output directory if it does not exist" do
    config = config_for(SessionRunnerFixture, methods: %i[shout])
    config.output_dir = File.join(@dir, "nested", "deeper")
    session = described_class.start(config)
    described_class.finish(session)
    expect(File).to exist(File.join(config.output_dir, "test.jsonl"))
  end

  it "tolerates a nil session on finish" do
    expect { described_class.finish(nil) }.not_to raise_error
  end
end
