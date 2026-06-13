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

  describe Ethotrace::Isolation::Box do
    # 越境を伴う実体分離・配信の検証は spec/isolation/box_isolation_spec.rb(RUBY_BOX 必須)。
    # ここでは Ruby::Box の有無に関わらず固定できる契約のみを確認する。
    describe ".available?" do
      it "reflects whether Ruby::Box is enabled in this runtime" do
        expected = defined?(Ruby::Box) && Ruby::Box.enabled?
        expect(described_class.available?).to eq(expected)
      end
    end

    context "when Ruby::Box is unavailable" do
      before { allow(described_class).to receive(:available?).and_return(false) }

      # 利用不可環境で install を試みたら、Null へのフォールバックを促す明示エラーを出す。
      it "raises a descriptive Ethotrace::Error on install_probe" do
        expect { described_class.new.install_probe(double("registry")) }
          .to raise_error(Ethotrace::Error, /RUBY_BOX=1.*Isolation::Null/m)
      end

      it "is a no-op on uninstall_probe before any box is installed" do
        expect { described_class.new.uninstall_probe(double("registry")) }.not_to raise_error
      end
    end
  end
end
