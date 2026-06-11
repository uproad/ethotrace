# frozen_string_literal: true

# エスケープ例外の direct / inherited 帰属を、実際の prepend ラッパーを通した
# ネスト呼び出しで検証する(Tracker.record_escape の結線を end-to-end で確認)。
RSpec.describe "error attribution through the wrapper" do
  before { Ethotrace::Wrapper.reset! }

  after do
    Ethotrace::Wrapper.reset!
    Ethotrace::Tracker.reset
  end

  let(:observations) { [] }

  before { Ethotrace::Wrapper.subscribe(->(ctx) { observations << ctx.to_observation }) }

  # 観測レコードを method 名で引けるようにする。
  def errors_by_method
    observations.to_h { |obs| [obs[:method][:name], obs[:errors]] }
  end

  it "tags the originating method direct and each caller inherited from its callee" do
    stub_const("Sample", Class.new do
      def a = b
      def b = c
      def c = raise(KeyError, "missing")
    end)
    %i[a b c].each { |name| Ethotrace::Wrapper.wrap(Sample, name) }

    expect { Sample.new.a }.to raise_error(KeyError, "missing")

    errors = errors_by_method
    expect(errors["c"]).to eq([{ class: "KeyError", origin: "direct", from: nil }])
    expect(errors["b"]).to eq([{ class: "KeyError", origin: "inherited", from: "Sample#c" }])
    expect(errors["a"]).to eq([{ class: "KeyError", origin: "inherited", from: "Sample#b" }])
  end

  it "does not record an exception that an intermediate method rescues" do
    stub_const("Guarded", Class.new do
      def outer = middle

      def middle
        inner
      rescue KeyError
        :handled
      end

      def inner = raise(KeyError, "missing")
    end)
    %i[outer middle inner].each { |name| Ethotrace::Wrapper.wrap(Guarded, name) }

    expect(Guarded.new.outer).to eq(:handled)

    errors = errors_by_method
    # inner はエスケープした(middle のユーザーコードが捕える前にラッパーを通る)。
    expect(errors["inner"]).to eq([{ class: "KeyError", origin: "direct", from: nil }])
    # middle / outer へは例外がエスケープしないため記録されない。
    expect(errors["middle"]).to eq([])
    expect(errors["outer"]).to eq([])
  end

  it "attributes the nearest wrapped callee even across an unwrapped frame" do
    stub_const("Mixed", Class.new do
      def a = unwrapped
      def unwrapped = c
      def c = raise(ArgumentError, "bad")
    end)
    # unwrapped は計装しない。
    Ethotrace::Wrapper.wrap(Mixed, :a)
    Ethotrace::Wrapper.wrap(Mixed, :c)

    expect { Mixed.new.a }.to raise_error(ArgumentError)

    errors = errors_by_method
    expect(errors["c"]).to eq([{ class: "ArgumentError", origin: "direct", from: nil }])
    # a から見た伝播元は、未計装の unwrapped を飛ばして最も近い被観測 callee の c。
    expect(errors["a"]).to eq([{ class: "ArgumentError", origin: "inherited", from: "Mixed#c" }])
  end
end
