# frozen_string_literal: true

# BoxBridge は box 空間で動く前提だが、Ruby::Box に依存しない純粋なグルーなので、
# 同一空間でも振る舞いを検証できる(connect=購読配線 / wrap=計装 / install_adapters /
# disconnect=解除)。box 越境そのものの検証は spec/isolation/box_isolation_spec.rb。
RSpec.describe Ethotrace::Isolation::BoxBridge do
  before do
    described_class.reset!
    Ethotrace::Collector.reset!
    Ethotrace::Wrapper.reset!
  end

  after do
    described_class.reset!
    Ethotrace::Collector.reset!
    Ethotrace::Wrapper.reset!
  end

  describe ".connect" do
    it "subscribes the root sink to the Collector" do
      sink = ->(_ctx) {}
      described_class.connect(sink)
      expect(Ethotrace::Collector.subscribers).to include(sink)
    end
  end

  describe ".wrap" do
    it "installs an observation wrapper on the named class in this space" do
      target = Class.new { def echo(arg) = arg }
      stub_const("BoxBridgeProbeTarget", target)

      expect(described_class.wrap("BoxBridgeProbeTarget", :echo)).to be(true)
      expect(Ethotrace::Wrapper.instrumented?(target, :echo)).to be(true)
    end
  end

  describe ".install_adapters" do
    it "instantiates and installs each named adapter via an Instrumenter" do
      installed = []
      adapter_class = Class.new do
        define_method(:install) { |instrumenter| installed << instrumenter }
        define_method(:uninstall) { |_instrumenter| nil }
      end
      stub_const("FakeBoxAdapter", adapter_class)

      described_class.install_adapters(["FakeBoxAdapter"])

      expect(installed.size).to eq(1)
      expect(installed.first).to be_a(Ethotrace::Instrumenter)
    end
  end

  describe ".disconnect" do
    it "uninstalls installed adapters and unsubscribes the sink" do
      events = []
      adapter_class = Class.new do
        define_method(:install) { |_instrumenter| events << :install }
        define_method(:uninstall) { |_instrumenter| events << :uninstall }
      end
      stub_const("FakeBoxAdapter", adapter_class)
      sink = ->(_ctx) {}

      described_class.connect(sink)
      described_class.install_adapters(["FakeBoxAdapter"])
      described_class.disconnect

      expect(events).to eq(%i[install uninstall])
      expect(Ethotrace::Collector.subscribers).not_to include(sink)
    end
  end
end
