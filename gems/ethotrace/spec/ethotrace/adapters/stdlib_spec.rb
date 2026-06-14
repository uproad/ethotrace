# frozen_string_literal: true

require "securerandom"
require "tmpdir"

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

  describe "env.write" do
    after { ENV.delete("ETHOTRACE_W") }

    it "records ENV#[]= with the key only and stays transparent" do
      reqs = requirements_during { ENV["ETHOTRACE_W"] = "v1" }
      expect(ENV.fetch("ETHOTRACE_W")).to eq("v1")
      expect(reqs).to eq([{ kind: "env.write", write: true, direct: true, from: nil,
                            detail: { key: "ETHOTRACE_W" } }])
    end

    it "records ENV#delete as a write" do
      ENV["ETHOTRACE_W"] = "v1"
      reqs = requirements_during { ENV.delete("ETHOTRACE_W") }
      expect(reqs.first).to include(kind: "env.write", detail: { key: "ETHOTRACE_W" })
    end
  end

  describe "io.read / io.write" do
    around do |example|
      Dir.mktmpdir { |dir| @dir = dir and example.run }
    end

    it "records File.write as io.write and File.read as io.read (with path/mode)" do
      path = File.join(@dir, "data.txt")
      write_reqs = requirements_during { File.write(path, "hello") }
      read_reqs = requirements_during { File.read(path) }

      expect(write_reqs.first).to include(kind: "io.write", write: true, detail: { path: path, mode: "w" })
      expect(read_reqs.first).to include(kind: "io.read", write: false, detail: { path: path, mode: "r" })
    end

    it "relativizes an io path under the base directory" do
      original = Ethotrace.base_dir
      Ethotrace.base_dir = @dir
      path = File.join(@dir, "data.txt")
      reqs = requirements_during { File.write(path, "hello") }
      expect(reqs.first[:detail][:path]).to eq("data.txt")
    ensure
      Ethotrace.base_dir = original
    end

    it "classifies File.open by mode" do
      path = File.join(@dir, "data.txt")
      # File.open(write) フックを試すのが目的。Style/FileWrite はこの構文の
      # 検査でクラッシュするため無効化する。
      reqs_w = requirements_during { File.open(path, "w") { |f| f.write("x") } } # rubocop:disable Style/FileWrite
      # File.open フック(read 既定)を試すのが目的なので、open のみ行う。
      reqs_r = requirements_during { File.open(path, &:path) }
      expect(reqs_w.first).to include(kind: "io.write", detail: { path: path, mode: "w" })
      expect(reqs_r.first).to include(kind: "io.read", detail: { path: path, mode: "r" })
    end
  end

  describe "process.exec" do
    it "records Kernel#system with the program name only (args masked) and runs it" do
      result = nil
      reqs = requirements_during { result = system("true") }
      expect(result).to be(true)
      expect(reqs).to eq([{ kind: "process.exec", write: true, direct: true, from: nil,
                            detail: { command: "true" } }])
    end

    it "records the backtick form" do
      reqs = requirements_during { `true` }
      expect(reqs.first).to include(kind: "process.exec", detail: { command: "true" })
    end

    describe ".mask_command" do
      it "keeps only the program name and drops arguments" do
        expect(described_class.mask_command(["psql -U user -W secret"])).to eq("psql")
        expect(described_class.mask_command(["ls", "-la"])).to eq("ls")
        expect(described_class.mask_command([{ "ENV" => "1" }, "ls", "-la"])).to eq("ls")
        expect(described_class.mask_command([["/bin/ls", "ls"], "-la"])).to eq("/bin/ls")
        expect(described_class.mask_command([])).to eq("?")
      end
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

  describe "effect span folding" do
    it "folds a stdlib raw effect into an enclosing effect span" do
      reqs = requirements_during do
        instrumenter.with_effect_span("db.query", write: false) { Time.now }
      end
      # 区間中の time.read はスパンへ畳み込まれ、db.query だけが残る。
      expect(reqs.map { |r| r[:kind] }).to eq(["db.query"])
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
