# frozen_string_literal: true

module Ethotrace
  # アダプタへ渡す計装ファサード。アダプタはこのオブジェクト経由でのみ core を
  # 操作する。core の物理機構({Wrapper} / {Tracker})への薄い委譲層であり、
  # アダプタを内部実装から切り離す安定境界となる。
  #
  # 現状の操作:
  # - {#wrap_method} — 観測ラッパーの設置
  # - {#record_effect} — Requirements チャネルへのエフェクト記録
  #
  # `with_effect_span` は後続 feature(エフェクトスパン)で追加する。
  class Instrumenter
    # 対象メソッドに観測ラッパーを設置する。二重 wrap は {Wrapper} が防ぐ。
    #
    # @return [Boolean] 新たに計装したら true、既に計装済みなら false。
    def wrap_method(klass, name, kind: :instance)
      Wrapper.wrap(klass, name, kind: kind)
    end

    # エフェクト(外部世界への接触)を記録する。帰属(direct / inherited)は
    # core が活性コールスタックから行う。アダプタのチョークポイントフックから
    # 呼ぶことを想定する。
    #
    # 再入ガード下で実行するため、トレーサ自身がフック対象を呼んだ場合(例:
    # JSONL ライターが Time.now を呼ぶ等)の自己記録・無限再帰を防ぐ。
    #
    # @param kind [String, Symbol] エフェクト語彙(例: "env.read")。
    # @param write [Boolean] 書き込み系か読み取り系か。
    # @param detail [Hash] エフェクト固有の詳細(機微情報は含めない)。
    def record_effect(kind, write:, **detail)
      ReentryGuard.guard { Tracker.record_effect(kind, write: write, **detail) }
    end
  end
end
