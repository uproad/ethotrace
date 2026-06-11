# frozen_string_literal: true

require "monitor"

module Ethotrace
  # Success / Error チャネルを観測する prepend ラッパーのオーケストレーション。
  #
  # {wrap} は計装レジストリで二重 wrap を防ぎつつ {Instrumentation} に横取り
  # モジュールの prepend を委ねる。ラッパーは {observe} を介して元メソッドを
  # `super` で呼び、戻り値(Success)とエスケープ例外(Error)を {CallContext}
  # へ記録する。完了したコンテキストは {subscribe} で登録した購読者(JSONL
  # ライター等)へ流す。
  #
  # 不変条件(CLAUDE.md「実装上の最重要ルール」):
  #
  # 1. **挙動を一切変えない**: 引数・ブロック・キーワードをそのまま委譲し、例外は
  #    `rescue Exception` で捕捉して必ず再送出する。可視性も {Instrumentation} が保存する。
  # 2. **再入ガード**: 記録処理は {ReentryGuard} の内側でのみ行い、`super` 自体は
  #    ガードの外で呼ぶ(ネストした被観測呼び出しを潰さないため)。記録中の
  #    内部エラーはユーザーに伝播させず観測のみ無効化する。
  # 3. **二重 wrap 禁止**: 計装レジストリ `(target, name, kind)` で管理する。
  #
  # 詳細は ethotrace-design-handoff.md §4.2 を参照。
  module Wrapper
    # 計装レジストリと購読者リストを保護するモニタ。計装はセットアップ時に
    # 行われるが、念のためスレッド安全にする。
    LOCK = Monitor.new

    @registry = {}     # { [target, name, kind] => true }
    @subscribers = []  # 完了した CallContext を受け取る callable 群
    @reported_internal_error = false

    class << self
      # 対象メソッドにラッパーを prepend する。
      #
      # @param klass [Module] 対象クラス/モジュール。
      # @param name [Symbol, String] メソッド名。
      # @param kind [Symbol] :instance(インスタンスメソッド)/ :singleton(特異メソッド)。
      # @return [Boolean] 新たに計装したら true、既に計装済みなら false。
      def wrap(klass, name, kind: :instance) # rubocop:disable Naming/PredicateMethod
        name = name.to_sym
        key = [Instrumentation.prepend_target(klass, kind), name, kind]

        LOCK.synchronize do
          return false if @registry.key?(key)

          Instrumentation.install(klass, name, kind)
          @registry[key] = true
        end
        true
      end

      # 対象メソッドが計装済みか。
      def instrumented?(klass, name, kind: :instance)
        key = [Instrumentation.prepend_target(klass, kind), name.to_sym, kind]
        LOCK.synchronize { @registry.key?(key) }
      end

      # 完了した観測(CallContext)の購読者を登録する。
      # JSONL ライター(feature/jsonl-writer)が利用する producer→consumer の継ぎ目。
      def subscribe(callable)
        LOCK.synchronize { @subscribers << callable }
        callable
      end

      # 現在の購読者一覧(コピー)。
      def subscribers
        LOCK.synchronize { @subscribers.dup }
      end

      # 計装レジストリと購読者を初期化する(主にテスト用)。
      # 既に prepend 済みのモジュールは外せないが、レジストリを空にすることで
      # 再 wrap を許可し、購読者を切り離す。
      def reset!
        LOCK.synchronize do
          @registry.clear
          @subscribers.clear
          @reported_internal_error = false
        end
      end

      # ラッパー本体。`super` を内側で呼ぶブロックを受け取り、三チャネル観測の
      # 開始・記録・終了を取り回す。生成メソッドから呼ばれる。
      #
      # @param descriptor [Hash] begin_call へ渡す記述子。
      def observe(descriptor, &)
        context = bookkeep { Tracker.begin_call(**descriptor) }
        # 再入中(記録のネスト)、または記録の内部エラー時は素通しする。
        return yield if context.nil?

        run_observed(context, &)
      end

      private

      # context を確立した状態で元メソッド(ブロック)を実行し、三チャネルを記録する。
      # 元の戻り値・例外はそのまま通し、記録は再入ガード下でのみ行う。
      def run_observed(context)
        result = yield
        bookkeep { context.record_return(result) }
        result
      rescue Exception => e # rubocop:disable Lint/RescueException
        # エスケープ例外を direct / inherited に帰属して記録し、必ず元の例外を
        # 再送出する(挙動を変えない)。
        bookkeep { Tracker.record_escape(context, e) }
        raise
      ensure
        bookkeep { conclude(context) }
      end

      # 呼び出し終了: スタックから降ろし、完了した観測を購読者へ流す。
      def conclude(context)
        Tracker.end_call(context)
        publish(context)
      end

      # 記録処理(トレーサ内部作業)を再入ガード下で実行する。
      # 再入時は nil を返してブロックを実行しない。内部エラーはユーザーへ
      # 伝播させず、観測のみ無効化して一度だけ警告する。
      def bookkeep
        ReentryGuard.guard do
          yield
        rescue StandardError => e
          report_internal_error(e)
          nil
        end
      end

      # 完了した CallContext を全購読者へ通知する。購読者の例外は他へ伝播させない。
      def publish(context)
        @subscribers.each do |callable|
          callable.call(context)
        rescue StandardError => e
          report_internal_error(e)
        end
      end

      def report_internal_error(error)
        return if @reported_internal_error

        @reported_internal_error = true
        warn "[ethotrace] internal error suppressed; observation disabled for this call: " \
             "#{error.class}: #{error.message}"
      end
    end
  end
end
