# frozen_string_literal: true

require "monitor"

module Ethotrace
  # 登録済みアダプタを保持し、ライフサイクルをファンアウトするレジストリ。
  #
  # テストハーネス(rspec/minitest アダプタ等)が起動時にアダプタを登録し、
  # 計装フェーズで {.install} を、セッション境界で {.start_session} /
  # {.end_session} を呼ぶ。全アダプタは共有の {Instrumenter} 経由で core を操作する。
  module AdapterRegistry
    LOCK = Monitor.new
    @adapters = []

    class << self
      # アダプタを登録する。同一クラスの二重登録は無視する。
      def register(adapter)
        LOCK.synchronize do
          @adapters << adapter unless @adapters.map(&:class).include?(adapter.class)
        end
        adapter
      end

      # 登録済みアダプタ一覧(コピー)。
      def adapters
        LOCK.synchronize { @adapters.dup }
      end

      # session レコード用の短い名前一覧(docs/schema.md §3 の `adapters`)。
      def names
        adapters.map(&:name)
      end

      # 登録を初期化する(主にテスト用)。
      def reset!
        LOCK.synchronize { @adapters.clear }
      end

      # 全アダプタにフックを設置させる。
      def install(instrumenter = Instrumenter.new)
        adapters.each { |adapter| adapter.install(instrumenter) }
        instrumenter
      end

      # 全アダプタにフックを解除させる。
      def uninstall(instrumenter = Instrumenter.new)
        adapters.each { |adapter| adapter.uninstall(instrumenter) }
        instrumenter
      end

      # 全アダプタへセッション開始を通知する。
      def start_session(session)
        adapters.each { |adapter| adapter.on_session_start(session) }
      end

      # 全アダプタへセッション終了を通知する。
      def end_session(session)
        adapters.each { |adapter| adapter.on_session_end(session) }
      end
    end
  end
end
