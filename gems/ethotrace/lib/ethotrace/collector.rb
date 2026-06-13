# frozen_string_literal: true

require "monitor"

module Ethotrace
  # 観測の **sink**(collector の配信端)。完了した観測({CallContext})を受け取り、
  # 登録された購読者(JSONL ライター等)へ配信する。
  #
  # collector / probe 分離(box-semantics.md)における collector 側の構成要素。
  # probe({Wrapper} の prepend 等)は完了した観測をここへ publish するだけで、
  # 配信先(購読者)を知らない。
  #
  # 自己適用(BoxIsolation, feature 4)では、box 内 probe が組み立てた CallContext は
  # データを丸ごと運ぶため、box 側 Collector に **root の sink へ橋渡しする購読者** を
  # 1 つ登録すれば、観測データが root の JSONL ライターまで届く。記録(Tracker)は
  # box ローカルのままでよく、root 側に必要なのはこの sink だけ、という構造になる。
  #
  # 並列実行に備えクラス状態はモニタで保護する(計装はセットアップ時が主だが安全側)。
  module Collector
    LOCK = Monitor.new
    @subscribers = [] # 完了した CallContext を受け取る callable 群

    class << self
      # 完了した観測(CallContext)の購読者を登録する。
      def subscribe(callable)
        LOCK.synchronize { @subscribers << callable }
        callable
      end

      # 購読者を解除する(セッション終了時など)。
      def unsubscribe(callable)
        LOCK.synchronize { @subscribers.delete(callable) }
        callable
      end

      # 現在の購読者一覧(コピー)。
      def subscribers
        LOCK.synchronize { @subscribers.dup }
      end

      # 完了した CallContext を全購読者へ配信する。購読者の例外は他へ伝播させず、
      # 観測のみ無効化する({Diagnostics} で一度だけ警告)。
      def publish(context)
        subscribers.each do |callable|
          callable.call(context)
        rescue StandardError => e
          Diagnostics.report_internal_error(e)
        end
      end

      # 購読者を初期化する(主にテスト用)。
      def reset!
        LOCK.synchronize { @subscribers.clear }
      end
    end
  end
end
