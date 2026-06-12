# frozen_string_literal: true

# 観測対象に渡すダックタイプのコラボレータ群。
#
# アクセサは attr_reader / Struct ではなく必ず def で定義する。Struct や
# attr_reader が生むアクセサは C 実装メソッドで、既定の引数プロトコル観測
# (TracePoint :call のみ)では捕捉されないため(:c_call はオプトイン)。

# --- Level 1: Gate#admit の visitor ----------------------------------------
# 内部表現は違う(@age を直接持つ / 生年から計算する)が、同じ #age プロトコル。

class Adult
  def initialize(age) = @age = age
  def age = @age
end

class Child
  def initialize(birth_year) = @birth_year = birth_year
  def age = 2026 - @birth_year
end

# --- Level 2: Pricing#quote の item / coupon -------------------------------

class Product
  def initialize(price:, category: :normal)
    @price = price
    @category = category
  end

  def price = @price
  def category = @category
end

class PercentCoupon
  def initialize(percent) = @percent = percent
  def discount(subtotal) = subtotal * @percent / 100
end

# --- Level 3: Dispatcher の build blueprint / charge account ----------------

class Blueprint
  def initialize(fields) = @fields = fields
  def fields = @fields
end

class Wallet
  def initialize(balance) = @balance = balance
  def balance = @balance
end
