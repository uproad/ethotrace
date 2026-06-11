# frozen_string_literal: true

require "ethotrace/cli"
require "tmpdir"

RSpec.describe Ethotrace::CLI::Reader do
  let(:err) { StringIO.new }

  def write_jsonl(dir, name, lines)
    path = File.join(dir, name)
    File.write(path, lines.join("\n"))
    path
  end

  def session_line(version: 1)
    JSON.generate(schema_version: version, type: "session", session: "s1")
  end

  def observation_line(version: 1, name: "m")
    JSON.generate(schema_version: version, type: "method_observation",
                  method: { owner: "O", name: name, kind: "instance" })
  end

  it "classifies session and method_observation records across files" do
    Dir.mktmpdir do |dir|
      a = write_jsonl(dir, "a.jsonl", [session_line, observation_line(name: "a")])
      b = write_jsonl(dir, "b.jsonl", [observation_line(name: "b")])
      result = described_class.new(warn_io: err).read([a, b])

      expect(result.sessions.size).to eq(1)
      expect(result.observations.map { |o| o[:method][:name] }).to eq(%w[a b])
    end
  end

  it "skips blank lines" do
    Dir.mktmpdir do |dir|
      path = write_jsonl(dir, "a.jsonl", [session_line, "", observation_line, ""])
      result = described_class.new(warn_io: err).read([path])
      expect(result.observations.size).to eq(1)
    end
  end

  it "warns and skips a malformed line without aborting" do
    Dir.mktmpdir do |dir|
      path = write_jsonl(dir, "a.jsonl", [observation_line, "{not json", observation_line])
      result = described_class.new(warn_io: err).read([path])
      expect(result.observations.size).to eq(2)
      expect(err.string).to match(/skipping .*a\.jsonl:2/)
    end
  end

  it "warns about a missing file but continues" do
    Dir.mktmpdir do |dir|
      path = write_jsonl(dir, "a.jsonl", [observation_line])
      result = described_class.new(warn_io: err).read([File.join(dir, "missing.jsonl"), path])
      expect(result.observations.size).to eq(1)
      expect(err.string).to match(/no such file/)
    end
  end

  it "warns when schema_version is mixed" do
    Dir.mktmpdir do |dir|
      path = write_jsonl(dir, "a.jsonl", [observation_line(version: 1), observation_line(version: 2)])
      described_class.new(warn_io: err).read([path])
      expect(err.string).to match(/mixed schema_version/)
    end
  end
end
