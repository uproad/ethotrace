# frozen_string_literal: true

RSpec.describe Ethotrace::Wrapper do
  # prepend は取り消せないため、各 example は毎回**新しい無名クラス**を計装する。
  # 計装レジストリ(Wrapper)・購読者(Collector)・警告フラグ(Diagnostics)を
  # reset! で初期化し、コールスタック(Tracker)も掃除する。
  before do
    described_class.reset!
    Ethotrace::Collector.reset!
    Ethotrace::Diagnostics.reset!
  end

  after do
    described_class.reset!
    Ethotrace::Collector.reset!
    Ethotrace::Diagnostics.reset!
    Ethotrace::Tracker.reset
  end

  # 完了した観測レコードを集める購読者(sink は Collector が持つ)。
  let(:observations) { [] }

  before { Ethotrace::Collector.subscribe(->(ctx) { observations << ctx.to_observation }) }

  def last_observation
    observations.last
  end

  describe "transparency (挙動を一切変えない)" do
    it "returns the value unchanged" do
      klass = Class.new { def double(num) = num * 2 }
      described_class.wrap(klass, :double)
      expect(klass.new.double(21)).to eq(42)
    end

    it "preserves return value identity" do
      klass = Class.new { def identity(obj) = obj }
      described_class.wrap(klass, :identity)
      token = Object.new
      expect(klass.new.identity(token)).to be(token)
    end

    it "delegates positional args, keyword args, and a block faithfully" do
      klass = Class.new { def echo(*args, **kwargs, &block) = [args, kwargs, block&.call] }
      described_class.wrap(klass, :echo)
      expect(klass.new.echo(1, 2, a: 3) { :from_block }).to eq([[1, 2], { a: 3 }, :from_block])
    end

    it "keeps an explicit positional hash positional (Ruby 3.x kwargs separation)" do
      klass = Class.new { def take(arg) = arg }
      described_class.wrap(klass, :take)
      expect(klass.new.take({ "k" => 1 })).to eq({ "k" => 1 })
    end

    it "re-raises the original escaped exception" do
      klass = Class.new { def boom = raise(ArgumentError, "no") }
      described_class.wrap(klass, :boom)
      expect { klass.new.boom }.to raise_error(ArgumentError, "no")
    end

    it "does not put the wrapper at the top of the backtrace" do
      klass = Class.new { def boom = raise("kaboom") }
      described_class.wrap(klass, :boom)
      klass.new.boom
    rescue StandardError => e
      expect(e.backtrace.first).to include("wrapper_spec.rb")
    end

    it "works on a frozen receiver" do
      klass = Class.new { def state = :ok }
      described_class.wrap(klass, :state)
      obj = klass.new.freeze
      expect(obj.state).to eq(:ok)
      expect(obj).to be_frozen
    end

    it "preserves a private method's visibility" do
      klass = Class.new do
        def call_secret = secret

        private

        def secret = 42
      end
      described_class.wrap(klass, :secret)
      obj = klass.new
      expect { obj.secret }.to raise_error(NoMethodError, /private/)
      expect(obj.call_secret).to eq(42)
    end

    it "preserves a protected method's visibility" do
      klass = Class.new do
        def compare(other) = balance <=> other.balance

        protected

        def balance = 100
      end
      described_class.wrap(klass, :balance)
      expect { klass.new.balance }.to raise_error(NoMethodError, /protected/)
      expect(klass.new.compare(klass.new)).to eq(0)
    end
  end

  describe "Success / Error recording" do
    it "records the return class on the Success channel" do
      klass = Class.new { def double(num) = num * 2 }
      described_class.wrap(klass, :double)
      klass.new.double(21)
      expect(last_observation[:return][:classes_seen]).to eq(["Integer"])
    end

    it "records an escaped exception as direct on the Error channel" do
      klass = Class.new { def boom = raise(ArgumentError, "no") }
      described_class.wrap(klass, :boom)
      expect { klass.new.boom }.to raise_error(ArgumentError)
      expect(last_observation[:errors])
        .to eq([{ class: "ArgumentError", origin: "direct", from: nil }])
    end

    it "captures the method descriptor and definition site" do
      klass = Class.new { def total = 0 }
      described_class.wrap(klass, :total)
      klass.new.total
      expect(last_observation[:method]).to include(name: "total", kind: "instance")
      expect(last_observation[:site][:path]).to end_with("wrapper_spec.rb")
      expect(last_observation[:site][:line]).to be_a(Integer)
    end

    it "instruments singleton methods" do
      klass = Class.new { def self.create(arg) = arg }
      described_class.wrap(klass, :create, kind: :singleton)
      expect(klass.create(7)).to eq(7)
      expect(last_observation[:method]).to include(name: "create", kind: "singleton")
    end
  end

  describe "re-entry guard and the call stack" do
    it "observes nested calls without suppressing the inner one" do
      klass = Class.new do
        def outer = inner + 1
        def inner = 41
      end
      described_class.wrap(klass, :outer)
      described_class.wrap(klass, :inner)
      expect(klass.new.outer).to eq(42)
      names = observations.map { |obs| obs[:method][:name] }
      # inner が先に完了し、outer が後に完了する。
      expect(names).to eq(%w[inner outer])
    end

    it "leaves the call stack balanced after a call" do
      klass = Class.new { def boom = raise("x") }
      described_class.wrap(klass, :boom)
      expect { klass.new.boom }.to raise_error("x")
      expect(Ethotrace::Tracker.active?).to be(false)
    end
  end

  describe "instrumentation registry (二重 wrap 禁止)" do
    it "wraps once and reports already-instrumented on the second attempt" do
      klass = Class.new { def total = 0 }
      expect(described_class.wrap(klass, :total)).to be(true)
      expect(described_class.wrap(klass, :total)).to be(false)
      expect(described_class.instrumented?(klass, :total)).to be(true)
    end

    it "records only one observation per call despite repeated wrap attempts" do
      klass = Class.new { def total = 0 }
      described_class.wrap(klass, :total)
      described_class.wrap(klass, :total)
      klass.new.total
      expect(observations.size).to eq(1)
    end

    it "tracks instance and singleton methods independently" do
      klass = Class.new do
        def build = :i
        def self.build = :s
      end
      described_class.wrap(klass, :build, kind: :instance)
      expect(described_class.instrumented?(klass, :build, kind: :singleton)).to be(false)
    end
  end

  describe "fail-safe (内部エラーをユーザーへ伝播させない)" do
    it "does not let a subscriber error break the user call, and warns once" do
      Ethotrace::Collector.subscribe(->(_ctx) { raise "subscriber boom" })
      klass = Class.new { def value = :ok }
      described_class.wrap(klass, :value)

      result = nil
      expect { result = klass.new.value }.to output(/internal error suppressed/).to_stderr
      expect(result).to eq(:ok)
    end
  end
end
