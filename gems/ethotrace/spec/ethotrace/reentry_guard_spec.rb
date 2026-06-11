# frozen_string_literal: true

RSpec.describe Ethotrace::ReentryGuard do
  # 各 example の独立性を保つため、フラグを必ず初期化する。
  after { Thread.current[described_class::KEY] = nil }

  describe ".guard" do
    it "executes the block and returns its value when not re-entering" do
      expect(described_class.guard { 42 }).to eq(42)
    end

    it "marks the thread as inside the tracer while the block runs" do
      observed = nil
      described_class.guard { observed = described_class.in_tracer? }
      expect(observed).to be(true)
    end

    it "suppresses the inner block on re-entry and returns nil" do
      inner_ran = false
      described_class.guard do
        described_class.guard { inner_ran = true }
      end
      expect(inner_ran).to be(false)
    end

    it "keeps the flag raised across a nested (suppressed) guard" do
      still_inside = nil
      described_class.guard do
        described_class.guard { :ignored }
        still_inside = described_class.in_tracer?
      end
      expect(still_inside).to be(true)
    end

    it "lowers the flag after the block completes" do
      described_class.guard { :done }
      expect(described_class.in_tracer?).to be(false)
    end

    it "lowers the flag even when the block raises" do
      expect { described_class.guard { raise "boom" } }.to raise_error("boom")
      expect(described_class.in_tracer?).to be(false)
    end

    it "re-raises exceptions from the block unchanged" do
      expect { described_class.guard { raise ArgumentError, "bad" } }
        .to raise_error(ArgumentError, "bad")
    end
  end

  describe ".in_tracer?" do
    it "is false outside any guard" do
      expect(described_class.in_tracer?).to be(false)
    end

    it "isolates the flag per thread" do
      described_class.guard do
        other = Thread.new { described_class.in_tracer? }.value
        # 別スレッドはこのスレッドのガード状態を共有しない。
        expect(other).to be(false)
      end
    end
  end
end
