# frozen_string_literal: true

module Ethotrace
  # 観測中のメソッド呼び出しのネストを管理するコールスタック。
  #
  # prepend ラッパーは呼び出しの開始で {begin_call} を呼んで {CallContext} を
  # 積み、終了(正常・例外いずれも ensure 経由)で {end_call} を呼んで降ろす。
  # 活性コンテキストの一覧(={call_stack})は帰属機構(feature/error-attribution)が
  # 走査し、エフェクト/例外を direct / inherited に振り分ける土台となる。
  #
  # スタックは Thread/Fiber ごとに独立する。`Thread.current[]` は **Fiber-local**
  # であるため、Fiber を切り替えると別の(空の)スタックを見ることになり、
  # 「呼び出しのネストは Fiber ごとに別物」という意味論と一致する。
  # 詳細は ethotrace-design-handoff.md §4.3 を参照。
  module Tracker
    # コールスタックを保持する Thread/Fiber-local のキー。
    STACK_KEY = :ethotrace_call_stack
    # 直近にエスケープ中の例外と、その伝播元(被観測 callee)記述子を保持する
    # Thread/Fiber-local のキー。例外帰属(direct / inherited)に使う。
    ESCAPE_KEY = :ethotrace_last_escape

    module_function

    # 呼び出しの開始: 記述子から {CallContext} を生成し、スタックへ積んで返す。
    #
    # 戻り値の context をラッパーが保持し、終了時に {end_call} へ渡す。
    # 引数は {CallContext#initialize} にそのまま委譲する。
    def begin_call(owner:, name:, kind:, site: nil)
      context = CallContext.new(owner: owner, name: name, kind: kind, site: site)
      call_stack.push(context)
      context
    end

    # 呼び出しの終了: context をスタックから確実に降ろす。
    #
    # 正常時はスタック末尾が context なので単純に pop する。Fiber 切り替えや
    # 異常経路でネストが食い違った場合でも、context とそれ以降に取り残された
    # 内側フレームをまとめて破棄し、スタックがリークしないようにする
    # (GC 後の object_id 再利用に備えた「必ず掃除する」原則の実践)。
    # context が既に無い場合は何もしない。
    def end_call(context)
      stack = call_stack
      if stack.last.equal?(context)
        stack.pop
      elsif (index = stack.rindex { |c| c.equal?(context) })
        stack.slice!(index..)
      end
      context
    end

    # 例外がこの context のメソッドをエスケープしたことを記録し、direct /
    # inherited を帰属する。各 prepend ラッパーの rescue から呼ばれる。
    #
    # 例外はコールスタックを下から上へ unwind し、各被観測フレームの rescue を
    # 順に通る。より深い被観測フレームが既に**同一の例外オブジェクト**を見て
    # いれば、この context にとっては callee からの伝播(inherited)であり、
    # `from` はその直近 callee のメソッド参照になる。まだ誰も見ていなければ、
    # 観測上はこのフレームで直接発生(direct)した扱いとする。
    #
    # 途中フレームのユーザーコードが rescue すれば、その上のラッパー rescue は
    # 発火しないため記録もされない(= エスケープした例外のみが残る)。
    def record_escape(context, exception)
      previous = Thread.current[ESCAPE_KEY]
      if previous && previous[:exception].equal?(exception)
        context.record_escaped_exception(exception, origin: "inherited", from: previous[:from])
      else
        context.record_escaped_exception(exception, origin: "direct", from: nil)
      end
      # 一つ外側のフレームから見た「伝播元」はこのフレーム自身になる。
      Thread.current[ESCAPE_KEY] = { exception: exception, from: method_ref(context) }
      exception
    end

    # context のメソッドを `Owner#name`(特異メソッドは `Owner.name`)形式で表す。
    def method_ref(context)
      separator = context.kind == :singleton ? "." : "#"
      "#{context.owner}#{separator}#{context.name}"
    end

    # 現在(最深)の活性コンテキスト。スタックが空なら nil。
    def current
      call_stack.last
    end

    # 現在の Thread/Fiber の活性コンテキストスタック(最古→最深の順)。
    # 帰属機構が走査する生の配列を返す。
    def call_stack
      Thread.current[STACK_KEY] ||= []
    end

    # いずれかの呼び出しを観測中か。
    def active?
      !call_stack.empty?
    end

    # 現在の Thread/Fiber のスタックと例外帰属状態を破棄する
    # (セッション境界やテスト用)。
    def reset
      Thread.current[STACK_KEY] = nil
      Thread.current[ESCAPE_KEY] = nil
    end
  end
end
