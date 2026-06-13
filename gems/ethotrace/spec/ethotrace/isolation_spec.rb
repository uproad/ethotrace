# frozen_string_literal: true

RSpec.describe Ethotrace::Isolation do
  describe Ethotrace::Isolation::Strategy do
    it "is an abstract contract: probe install/uninstall must be implemented" do
      strategy = described_class.new
      expect { strategy.install_probe(double) }.to raise_error(NotImplementedError)
      expect { strategy.uninstall_probe(double) }.to raise_error(NotImplementedError)
    end
  end

  describe Ethotrace::Isolation::Null do
    subject(:isolation) { described_class.new }

    # 既定戦略は同一空間でアダプタを設置/解除する(隔離しない)。
    # registry へ install/uninstall をそのまま委譲することを固定する。
    it "delegates probe install to the registry in the same space" do
      registry = double("registry", install: :installed)
      isolation.install_probe(registry)
      expect(registry).to have_received(:install)
    end

    it "delegates probe uninstall to the registry in the same space" do
      registry = double("registry", uninstall: :uninstalled)
      isolation.uninstall_probe(registry)
      expect(registry).to have_received(:uninstall)
    end
  end
end
