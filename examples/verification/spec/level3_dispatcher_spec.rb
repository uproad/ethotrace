# frozen_string_literal: true

# Dispatcher#call の全分岐を通す高カバレッジ spec。
# return 10 クラス + error 7 種(うち RuntimeError は Ledger#charge からの inherited)
# + Requirements 3 種(env.read/time.read/random.read)を観測させる。
RSpec.describe Dispatcher do
  subject(:dispatcher) { described_class.new }

  describe "戻り値が分岐するコマンド" do
    it ":ping -> true (TrueClass)" do
      expect(dispatcher.call(:ping)).to be(true)
    end

    it ":pong -> false (FalseClass)" do
      expect(dispatcher.call(:pong)).to be(false)
    end

    it ":name -> String" do
      expect(dispatcher.call(:name)).to eq("dispatcher")
    end

    it ":count -> Integer(可変長引数の数)" do
      expect(dispatcher.call(:count, :a, :b, :c)).to eq(3)
    end

    it ":ratio -> Float" do
      expect(dispatcher.call(:ratio, 3, 2)).to eq(1.5)
    end

    it ":pick -> Symbol(キーワード引数)" do
      expect(dispatcher.call(:pick, from: :north)).to eq(:north)
    end

    it ":stamp -> Integer([req] time.read)" do
      expect(dispatcher.call(:stamp)).to be_a(Integer)
    end

    it ":dice -> Integer([req] random.read)" do
      expect(dispatcher.call(:dice)).to be_between(1, 6)
    end

    it ":build -> Result(独自クラス, [protocol] blueprint#fields)" do
      result = dispatcher.call(:build, Blueprint.new({ a: 1 }))
      expect(result).to eq(Result.new(command: :build, value: { a: 1 }))
    end

    it ":collect -> Array(ブロック)" do
      expect(dispatcher.call(:collect, 1, 2, 3) { |n| n * 2 }).to eq([2, 4, 6])
    end

    it ":meta -> Hash" do
      expect(dispatcher.call(:meta, :x, :y)).to eq({ command: :meta, argc: 2 })
    end

    it ":void -> nil (NilClass)" do
      expect(dispatcher.call(:void)).to be_nil
    end

    it ":charge -> Integer([protocol] account#balance)" do
      expect(dispatcher.call(:charge, Wallet.new(100), 30)).to eq(70)
    end
  end

  describe "環境変数を読むコマンド([req] env.read)" do
    around do |example|
      original = ENV.fetch("GREETING", nil)
      ENV["GREETING"] = "hi"
      example.run
    ensure
      ENV["GREETING"] = original
    end

    it ":env -> Symbol(環境変数の値)" do
      expect(dispatcher.call(:env, key: "GREETING")).to eq(:hi)
    end

    it "環境変数が無ければ KeyError" do
      ENV.delete("GREETING")
      expect { dispatcher.call(:env, key: "GREETING") }.to raise_error(KeyError)
    end
  end

  describe "エラーが分岐するコマンド" do
    it ":ratio は引数が足りないと ArgumentError" do
      expect { dispatcher.call(:ratio, 3) }.to raise_error(ArgumentError)
    end

    it ":ratio は 0 除算で ZeroDivisionError" do
      expect { dispatcher.call(:ratio, 3, 0) }.to raise_error(ZeroDivisionError)
    end

    it ":pick は :from が無いと KeyError" do
      expect { dispatcher.call(:pick) }.to raise_error(KeyError)
    end

    it ":build は不適格な blueprint で TypeError" do
      expect { dispatcher.call(:build, 42) }.to raise_error(TypeError)
    end

    it ":collect はブロック無しで ArgumentError" do
      expect { dispatcher.call(:collect, 1, 2) }.to raise_error(ArgumentError)
    end

    # Ledger#charge が送出した RuntimeError は Dispatcher#call をエスケープし、
    # Dispatcher 側の観測には origin: inherited(from: Ledger#charge)で記録される。
    it ":charge は残高不足で RuntimeError(inherited)" do
      expect { dispatcher.call(:charge, Wallet.new(10), 50) }.to raise_error(RuntimeError)
    end

    it ":boom は DispatchError(direct)" do
      expect { dispatcher.call(:boom) }.to raise_error(DispatchError)
    end

    it "未知のコマンドは UnknownCommand(direct)" do
      expect { dispatcher.call(:nope) }.to raise_error(UnknownCommand)
    end
  end
end
