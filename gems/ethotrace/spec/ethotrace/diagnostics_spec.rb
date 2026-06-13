# frozen_string_literal: true

RSpec.describe Ethotrace::Diagnostics do
  after { described_class.reset! }

  describe ".report_internal_error" do
    it "warns once and suppresses subsequent reports until reset" do
      described_class.reset!

      error = RuntimeError.new("boom")
      expect { described_class.report_internal_error(error) }
        .to output(/internal error suppressed; observation disabled.*RuntimeError: boom/).to_stderr
      # 2 回目はノイズにならないよう静かに無視する。
      expect { described_class.report_internal_error(error) }.not_to output.to_stderr

      described_class.reset!
      expect { described_class.report_internal_error(error) }
        .to output(/internal error suppressed/).to_stderr
    end
  end
end
