# frozen_string_literal: true

RSpec.describe Ethotrace::PathNormalizer do
  describe ".relativize" do
    let(:base) { "/proj/root" }

    it "folds a path under the base directory to a base-relative path" do
      expect(described_class.relativize("/proj/root/gems/a/lib/x.rb", base: base))
        .to eq("gems/a/lib/x.rb")
    end

    it "keeps a path outside the base directory absolute (external resource)" do
      expect(described_class.relativize("/opt/gems/json/x.rb", base: base))
        .to eq("/opt/gems/json/x.rb")
    end

    it "expands a relative path against the base before folding" do
      expect(described_class.relativize("gems/a.rb", base: base)).to eq("gems/a.rb")
    end

    it "does not treat a sibling directory sharing a prefix as inside the base" do
      # "/proj/root-extra" は "/proj/root" の接頭ではあるが配下ではない。
      expect(described_class.relativize("/proj/root-extra/x.rb", base: base))
        .to eq("/proj/root-extra/x.rb")
    end

    it "returns the path unchanged when there is no base" do
      expect(described_class.relativize("/anything/x.rb", base: nil)).to eq("/anything/x.rb")
    end

    it "passes nil through" do
      expect(described_class.relativize(nil, base: base)).to be_nil
    end

    it "defaults the base to Ethotrace.base_dir" do
      expect(described_class.relativize("#{Ethotrace.base_dir}/here.rb")).to eq("here.rb")
    end
  end
end
