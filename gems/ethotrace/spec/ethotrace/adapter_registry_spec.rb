# frozen_string_literal: true

RSpec.describe Ethotrace::AdapterRegistry do
  before { described_class.reset! }

  after { described_class.reset! }

  # 呼ばれたライフサイクルを記録する fake アダプタ。名前は引数で差し替えられる。
  let(:fake_adapter_class) do
    Class.new(Ethotrace::Adapter) do
      attr_reader :name, :events

      def initialize(name = "fake")
        super()
        @name = name
        @events = []
      end

      def install(instrumenter) = @events << [:install, instrumenter]
      def uninstall(instrumenter) = @events << [:uninstall, instrumenter]
      def on_session_start(session) = @events << [:start, session]
      def on_session_end(session) = @events << [:end, session]
    end
  end

  describe ".register" do
    it "registers an adapter and exposes it" do
      adapter = fake_adapter_class.new
      described_class.register(adapter)
      expect(described_class.adapters).to eq([adapter])
    end

    it "ignores a second registration of the same adapter class" do
      described_class.register(fake_adapter_class.new)
      described_class.register(fake_adapter_class.new)
      expect(described_class.adapters.size).to eq(1)
    end

    it "exposes the adapter names for the session record" do
      # 別クラスにするため一方をサブクラス化(同一クラスは二重登録されないため)。
      described_class.register(fake_adapter_class.new("stdlib"))
      described_class.register(Class.new(fake_adapter_class).new("rspec"))
      expect(described_class.names).to eq(%w[stdlib rspec])
    end
  end

  describe "lifecycle fan-out" do
    it "installs every adapter with a shared instrumenter" do
      adapter = fake_adapter_class.new
      described_class.register(adapter)
      instrumenter = described_class.install
      expect(adapter.events).to eq([[:install, instrumenter]])
      expect(instrumenter).to be_a(Ethotrace::Instrumenter)
    end

    it "notifies every adapter of session start and end" do
      adapter = fake_adapter_class.new
      described_class.register(adapter)
      described_class.start_session("rspec-w1")
      described_class.end_session("rspec-w1")
      expect(adapter.events).to eq([[:start, "rspec-w1"], [:end, "rspec-w1"]])
    end

    it "uninstalls every adapter" do
      adapter = fake_adapter_class.new
      described_class.register(adapter)
      described_class.uninstall
      expect(adapter.events.map(&:first)).to eq([:uninstall])
    end
  end

  describe ".reset!" do
    it "clears the registry" do
      described_class.register(fake_adapter_class.new)
      described_class.reset!
      expect(described_class.adapters).to be_empty
    end
  end
end
