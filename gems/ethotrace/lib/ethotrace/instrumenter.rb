# frozen_string_literal: true

module Ethotrace
  # アダプタへ渡す計装ファサード。アダプタはこのオブジェクト経由でのみ core を
  # 操作する。core の物理機構({Wrapper} / {Tracker})への薄い委譲層であり、
  # アダプタを内部実装から切り離す安定境界となる。
  #
  # 現状の操作:
  # - {#wrap_method} — 観測ラッパーの設置
  #
  # `record_effect` / `with_effect_span` は後続 feature(Requirements 帰属・
  # エフェクトスパン)で追加する。
  class Instrumenter
    # 対象メソッドに観測ラッパーを設置する。二重 wrap は {Wrapper} が防ぐ。
    #
    # @return [Boolean] 新たに計装したら true、既に計装済みなら false。
    def wrap_method(klass, name, kind: :instance)
      Wrapper.wrap(klass, name, kind: kind)
    end
  end
end
