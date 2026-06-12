# frozen_string_literal: true

RSpec.describe Ethotrace::Collector do
  before do
    described_class.reset!
    Ethotrace::Diagnostics.reset!
  end

  after do
    described_class.reset!
    Ethotrace::Diagnostics.reset!
  end

  describe "subscriber registry" do
    it "delivers a published context to every subscriber" do
      seen = []
      described_class.subscribe(->(ctx) { seen << "a:#{ctx}" })
      described_class.subscribe(->(ctx) { seen << "b:#{ctx}" })

      described_class.publish("obs")

      expect(seen).to eq(["a:obs", "b:obs"])
    end

    it "stops delivering after a subscriber is removed" do
      seen = []
      sub = described_class.subscribe(->(ctx) { seen << ctx })
      described_class.unsubscribe(sub)

      described_class.publish(:observation)

      expect(seen).to be_empty
    end

    it "clears subscribers on reset!" do
      described_class.subscribe(->(_ctx) { raise "should not be called" })
      described_class.reset!

      expect { described_class.publish(:observation) }.not_to raise_error
    end
  end

  describe "fail-safe publishing" do
    # 購読者の例外は他の購読者・呼び出し元へ伝播させず、Diagnostics で一度だけ警告する。
    it "isolates a failing subscriber and still notifies the others, warning once" do
      delivered = []
      described_class.subscribe(->(_ctx) { raise "boom" })
      described_class.subscribe(->(ctx) { delivered << ctx })

      expect { described_class.publish(:observation) }
        .to output(/internal error suppressed/).to_stderr

      expect(delivered).to eq([:observation])
    end
  end
end
