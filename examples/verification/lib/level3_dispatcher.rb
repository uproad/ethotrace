# frozen_string_literal: true

# 複雑さ Level 3 — 戻り値 10 種以上 / エラー 7 種 / 依存 3(ENV / Time / Random)。
#
# 可変長引数(*args)・キーワード引数(**opts)・ブロック(&block)を取り、
# command によって戻り値の型もエラーも呼ぶ依存先も総取り替えになる「頭が痛くなる」
# メソッド。観測すると、ひとつのメソッドに 10 を超える return クラスと 7 種の
# エラー(うち RuntimeError は被観測 callee Ledger#charge からの inherited 帰属)、
# 3 つの Requirements が畳み込まれて現れる。

# 独自エラー階層。UnknownCommand は DispatchError を継承する。
class DispatchError < StandardError; end
class UnknownCommand < DispatchError; end

# 独自戻り値クラス。return チャネルに固有クラス名 "Result" として現れる。
Result = Data.define(:command, :value)

# 被観測の下位サービス。Dispatcher#call から呼ばれ、例外を inherited 帰属させる材料になる。
class Ledger
  # account から amount を引いて新残高を返す。残高不足は RuntimeError。
  #
  # 戻り値: Integer / エラー: RuntimeError
  def charge(account, amount)
    raise "insufficient funds" if amount > account.balance # [protocol] account#balance
    account.balance - amount
  end
end

class Dispatcher
  def initialize(ledger = Ledger.new)
    @ledger = ledger
  end

  # command: 実行する操作(Symbol)。args / opts / block の意味は command 依存。
  #
  # 戻り値:
  #   TrueClass / FalseClass / String / Integer / Float / Symbol /
  #   Array / Hash / NilClass / Result(独自) の 10 クラス
  # エラー:
  #   ArgumentError / TypeError / ZeroDivisionError / KeyError /
  #   DispatchError / UnknownCommand(direct)、RuntimeError(inherited)
  # 依存:
  #   env.read(:env)/ time.read(:stamp)/ random.read(:dice)
  def call(command, *args, **opts, &block)
    case command
    when :ping   then true                       # [return] TrueClass
    when :pong   then false                      # [return] FalseClass
    when :name   then "dispatcher"               # [return] String
    when :count  then args.size                  # [return] Integer
    when :ratio  then ratio(*args)               # [return] Float  / ArgumentError / ZeroDivisionError
    when :pick   then opts.fetch(:from)          # [return] Symbol / KeyError(:from 欠落)
    when :env    then read_env(opts)             # [return] Symbol / KeyError([req] env.read)
    when :stamp  then Time.now.to_i              # [return] Integer([req] time.read)
    when :dice   then Random.rand(6) + 1         # [return] Integer([req] random.read)
    when :build  then build(args.first)          # [return] Result / TypeError
    when :collect then collect(args, &block)     # [return] Array / ArgumentError(block 必須)
    when :meta   then { command: command, argc: args.size } # [return] Hash
    when :void   then nil                        # [return] NilClass
    when :charge then @ledger.charge(args[0], args[1]) # [return] Integer / RuntimeError(inherited)
    when :boom   then raise DispatchError, "boom"      # [error] DispatchError(direct)
    else raise UnknownCommand, "no such command: #{command}" # [error] UnknownCommand(direct)
    end
  end

  private

  # 2 数の比を Float で返す。引数欠落は ArgumentError、0 除算は ZeroDivisionError。
  def ratio(numerator = nil, denominator = nil)
    raise ArgumentError, "two numbers required" if numerator.nil? || denominator.nil?
    raise ZeroDivisionError, "denominator is zero" if denominator.zero?

    numerator.fdiv(denominator)
  end

  # opts の :key で示された環境変数を Symbol で返す。[req] env.read
  def read_env(opts)
    key = opts.fetch(:key) # opts に :key が無ければ KeyError(direct)
    ENV.fetch(key).to_sym  # 環境変数が無ければ KeyError(direct)。読み取りは env.read。
  end

  # blueprint#fields を包んだ Result を返す。blueprint が不適格なら TypeError。
  def build(blueprint)
    raise TypeError, "blueprint must respond to #fields" unless blueprint.respond_to?(:fields)

    Result.new(command: :build, value: blueprint.fields) # [protocol] blueprint#fields
  end

  # 各要素にブロックを適用した配列を返す。ブロック未指定は ArgumentError。
  def collect(items, &block)
    raise ArgumentError, "block required" unless block

    items.map(&block)
  end
end
