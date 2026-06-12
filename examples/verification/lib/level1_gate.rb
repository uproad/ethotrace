# frozen_string_literal: true

# 複雑さ Level 1 — 戻り値 3 種 / エラー 1 種 / 依存 0。
#
# 入門用。分岐は素直で、引数プロトコルは visitor#age のみ。観測すると
# return チャネルに NilClass / Symbol / Integer の 3 クラスが、Error チャネルに
# ArgumentError が現れる。
class Gate
  # visitor: #age に応答する何か(公称型は問わない)。nil も受け取る。
  #
  # 戻り値: NilClass(来訪者なし)/ Symbol(:minor)/ Integer(入場年齢)
  # エラー : ArgumentError(年齢が負)
  def admit(visitor)
    return nil if visitor.nil? # [return] NilClass

    age = visitor.age          # [protocol] visitor#age
    raise ArgumentError, "age must be >= 0" if age.negative? # [error] ArgumentError

    return :minor if age < 18  # [return] Symbol
    age                        # [return] Integer
  end
end
