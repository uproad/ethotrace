# frozen_string_literal: true

module Ethotrace
  # 再入ガード(最重要の基盤)。
  #
  # トレーサの記録処理は Time の取得や Hash 操作などを普通に行うため、
  # それ自身が計装フックを発火させ、無限再帰に陥る。これを防ぐため、
  # Thread/Fiber-local のフラグでトレーサ内部への再入を遮断する。
  #
  # フラグは Thread.current に保持するため、スレッドごとに独立する。
  # 詳細は ethotrace-design-handoff.md §4.5 を参照。
  module ReentryGuard
    # トレーサ内部にいることを示す Thread-local フラグのキー。
    KEY = :ethotrace_in_tracer

    module_function

    # トレーサ内部処理をブロックとして実行する。
    #
    # すでにトレーサ内部にいる場合(再入)はブロックを実行せず nil を返す。
    # これにより記録処理が自身のフックを再発火させても、内側の記録は
    # 静かに抑制される。最外周の guard だけがフラグの所有権を持ち、
    # ensure でフラグを確実に下ろす(ブロックが例外を投げても復元する)。
    def guard
      return nil if Thread.current[KEY]

      Thread.current[KEY] = true
      begin
        yield
      ensure
        Thread.current[KEY] = false
      end
    end

    # 現在のスレッドがトレーサ内部にいるか。
    def in_tracer?
      Thread.current[KEY] == true
    end
  end
end
