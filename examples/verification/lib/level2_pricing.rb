# frozen_string_literal: true

# 複雑さ Level 2 — 戻り値 5 種 / エラー 3 種 / 依存 2(ENV / Time)。
#
# キーワード引数・任意引数(coupon)・独自戻り値クラス(Money)を持つ中級。
# 条件によってプロトコルも変わる(coupon#discount は coupon があるときだけ呼ぶ)。

# 金額を表す独自クラス。return チャネルに固有クラス名 "Money" として現れる。
class Money
  attr_reader :cents

  def initialize(cents) = @cents = cents
  def +(other) = Money.new(cents + other.cents)
  def ==(other) = other.is_a?(Money) && cents == other.cents
end

class Pricing
  FREE = :free

  # item     : #price と #category に応答する何か。
  # quantity : 整数(キーワード必須)。
  # coupon   : #discount(subtotal) に応答する何か(任意)。
  #
  # 戻り値: NilClass / Symbol(:free)/ Integer(0)/ Float / Money
  # エラー : ArgumentError(数量が負)/ TypeError(price が非整数)/ KeyError(TAX_RATE 未設定)
  def quote(item, quantity:, coupon: nil)
    raise ArgumentError, "quantity must be >= 0" if quantity.negative? # [error] ArgumentError
    return nil if quantity.zero?                                       # [return] NilClass

    category = item.category                       # [protocol] item#category
    return FREE if category == :sample             # [return] Symbol

    unit = item.price                              # [protocol] item#price
    raise TypeError, "price must be Integer" unless unit.is_a?(Integer) # [error] TypeError

    subtotal = unit * quantity
    subtotal -= coupon.discount(subtotal) if coupon # [protocol] coupon#discount(条件付き)
    return 0 if subtotal <= 0                        # [return] Integer(割引で消えた)

    rate  = Float(ENV.fetch("TAX_RATE"))            # [req] env.read / 未設定なら KeyError
    taxed = (subtotal * (1 + rate)).round

    return taxed.to_f if happy_hour?                # [return] Float(ハッピーアワー)
    Money.new(taxed)                                # [return] Money(通常)
  end

  private

  # 現在時刻でハッピーアワーを判定する。[req] time.read
  def happy_hour?
    Time.now.hour.between?(17, 19)
  end
end
