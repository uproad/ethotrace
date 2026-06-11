# frozen_string_literal: true

module Ethotrace
  # アダプタへ渡す計装ファサード。アダプタはこのオブジェクト経由でのみ core を
  # 操作する。core の物理機構({Wrapper} / {Tracker})への薄い委譲層であり、
  # アダプタを内部実装から切り離す安定境界となる。
  #
  # 現状の操作:
  # - {#wrap_method} — 観測ラッパーの設置
  # - {#record_effect} — Requirements チャネルへのエフェクト記録
  # - {#with_effect_span} — エフェクト区間の宣言(下位の生エフェクトを畳み込む)
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

    # エフェクト区間を宣言する。区間の効果(例: "db.query")を活性スタックへ
    # 記録し、ブロック実行中に発火した**生のエフェクト**(下位の実装詳細、例:
    # ソケットへの io.write)は畳み込んで抑制する。OpenTelemetry のスパン階層と
    # 同型で、上位アダプタの意味的なエフェクトと下位の重複記録を切り分ける。
    #
    # ブロックの戻り値をそのまま返す(計装対象の挙動を変えない)。区間の効果記録は
    # 再入ガード下で行うが、ブロック自体はガード外で実行する(ネストした被観測
    # 呼び出しを潰さないため)。
    #
    # @param kind [String, Symbol] エフェクト語彙(例: "db.query")。
    # @param write [Boolean] 書き込み系か読み取り系か。
    # @param detail [Hash] エフェクト固有の詳細(機微情報は含めない)。
    def with_effect_span(kind, write:, **detail)
      ReentryGuard.guard { Tracker.record_span_effect(kind, write: write, **detail) }
      Tracker.enter_effect_span
      begin
        yield
      ensure
        Tracker.leave_effect_span
      end
    end
  end
end
