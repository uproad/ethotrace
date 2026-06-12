# frozen_string_literal: true

# Gate#admit の全分岐を通す高カバレッジ spec。
# return 3 種(NilClass/Symbol/Integer)+ error 1 種(ArgumentError)を観測させる。
RSpec.describe Gate do
  subject(:gate) { described_class.new }

  it "returns nil when there is no visitor" do
    expect(gate.admit(nil)).to be_nil
  end

  it "returns :minor for a visitor under 18" do
    expect(gate.admit(Adult.new(15))).to eq(:minor)
  end

  it "returns the age (Integer) for an adult visitor" do
    expect(gate.admit(Adult.new(30))).to eq(30)
  end

  # 同じ #age プロトコルを満たす別クラスでも観測契約は 1 つに集約される。
  it "accepts a different class with the same #age protocol" do
    expect(gate.admit(Child.new(1990))).to eq(36)
  end

  it "raises ArgumentError for a negative age" do
    expect { gate.admit(Adult.new(-1)) }.to raise_error(ArgumentError)
  end
end
