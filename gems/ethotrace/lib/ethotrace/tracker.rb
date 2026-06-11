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
    # 活性なエフェクトスパンの深さを保持する Thread/Fiber-local のキー。
    SPAN_KEY = :ethotrace_effect_span_depth

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
        # 取り残された内側フレームも追跡テーブルから掃除する。
        stack.slice!(index..).each { |c| ArgumentTable.untrack(c) }
      end
      ArgumentTable.untrack(context)
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

    # エフェクト(外部世界への接触)を活性コールスタック全段へ帰属する。
    #
    # 例外と違いエフェクトは 1 点で発火するため、発火時点の活性スタックを
    # 一度に走査して帰属できる(ethotrace-design-handoff.md §4.4)。最深フレームは
    # 当該メソッド自身での発火(direct)、それより外のフレームは callee からの
    # 継承(inherited)で、`from` は直近 callee のメソッド参照になる。観測中の
    # メソッドが無い(スタックが空)場合は帰属先が無いので何もしない。
    #
    # 再入ガードは公開境界({Instrumenter#record_effect})が担うため、ここでは
    # 純粋な帰属のみを行う。
    #
    # エフェクトスパン({Instrumenter#with_effect_span})が活性な間は、生の
    # エフェクトはスパンへ畳み込むため記録しない(下位の実装詳細の重複記録を防ぐ)。
    def record_effect(kind, write:, **detail)
      return nil if effect_span_active?

      attribute_effect(kind, write: write, **detail)
    end

    # スパン宣言時の効果。スパンによる抑制を受けず、常に活性スタックへ帰属する。
    def record_span_effect(kind, write:, **detail)
      attribute_effect(kind, write: write, **detail)
    end

    # エフェクトを活性コールスタック全段へ帰属する(抑制判定なし)。
    def attribute_effect(kind, write:, **detail)
      stack = call_stack
      deepest = stack.size - 1
      stack.each_with_index do |context, index|
        direct = index == deepest
        from = direct ? nil : method_ref(stack[index + 1])
        context.add_requirement(kind, write: write, direct: direct, from: from, detail: detail)
      end
      nil
    end

    # エフェクトスパンに入る(Fiber-local の深さを増やす)。区間中の生エフェクトは
    # 抑制される。{Instrumenter#with_effect_span} から呼ばれる。
    def enter_effect_span
      Thread.current[SPAN_KEY] = effect_span_depth + 1
    end

    # エフェクトスパンから出る。深さは 0 未満にならない。
    def leave_effect_span
      Thread.current[SPAN_KEY] = [effect_span_depth - 1, 0].max
    end

    # いずれかのエフェクトスパンが活性か。
    def effect_span_active?
      effect_span_depth.positive?
    end

    # 現在の Fiber のエフェクトスパンの深さ。
    def effect_span_depth
      Thread.current[SPAN_KEY] || 0
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
      Thread.current[SPAN_KEY] = nil
      ArgumentTable.reset
    end
  end
end
