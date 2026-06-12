# frozen_string_literal: true

# Pricing#quote の全分岐を通す高カバレッジ spec。
# return 5 種(NilClass/Symbol/Integer/Float/Money)+ error 3 種
# (ArgumentError/TypeError/KeyError)+ Requirements(env.read/time.read)を観測させる。
RSpec.describe Pricing do
  subject(:pricing) { described_class.new }

  let(:item) { Product.new(price: 100, category: :normal) }

  # TAX_RATE はほとんどの例で必要。例ごとに設定し、終わったら戻す。
  around do |example|
    original = ENV.fetch("TAX_RATE", nil)
    ENV["TAX_RATE"] = "0.10"
    example.run
  ensure
    ENV["TAX_RATE"] = original
  end

  it "raises ArgumentError for a negative quantity" do
    expect { pricing.quote(item, quantity: -1) }.to raise_error(ArgumentError)
  end

  it "returns nil for zero quantity" do
    expect(pricing.quote(item, quantity: 0)).to be_nil
  end

  it "returns :free (Symbol) for a sample item" do
    sample = Product.new(price: 100, category: :sample)
    expect(pricing.quote(sample, quantity: 3)).to eq(:free)
  end

  it "raises TypeError when price is not an Integer" do
    weird = Product.new(price: "100", category: :normal)
    expect { pricing.quote(weird, quantity: 1) }.to raise_error(TypeError)
  end

  it "returns 0 (Integer) when a coupon wipes out the subtotal" do
    full_off = PercentCoupon.new(100)
    expect(pricing.quote(item, quantity: 2, coupon: full_off)).to eq(0)
  end

  it "raises KeyError when TAX_RATE is unset" do
    ENV.delete("TAX_RATE")
    expect { pricing.quote(item, quantity: 1) }.to raise_error(KeyError)
  end

  # 分岐の確定化は private な happy_hour? をスタブして行う。
  # 注: Time.now そのものを stub すると、ethotrace のチョークポイント(prepend フック)
  # より前に rspec-mocks が割り込み、実際の Time.now が走らないため time.read が
  # 記録されない。「依存をモックすると Requirement は観測されない」を避けるため、
  # ここでは Time ではなく判定メソッドを差し替える。
  context "during happy hour" do
    before { allow(pricing).to receive(:happy_hour?).and_return(true) }

    it "returns a Float" do
      expect(pricing.quote(item, quantity: 1)).to be_a(Float)
    end
  end

  context "outside happy hour" do
    before { allow(pricing).to receive(:happy_hour?).and_return(false) }

    it "returns Money" do
      # 100 * 2 * 1.10 = 220
      expect(pricing.quote(item, quantity: 2)).to eq(Money.new(220))
    end

    it "applies a coupon discount before tax" do
      half_off = PercentCoupon.new(50)
      # (100 * 2 - 100) * 1.10 = 110
      expect(pricing.quote(item, quantity: 2, coupon: half_off)).to eq(Money.new(110))
    end
  end

  # happy_hour? を差し替えず実時計を読ませ、time.read を観測させる例。
  # 戻り値は実時刻に依存するため Float / Money のどちらかとしてのみ検証する。
  it "reads the wall clock ([req] time.read)" do
    result = pricing.quote(item, quantity: 1)
    expect(result).to be_a(Money).or be_a(Float)
  end
end
