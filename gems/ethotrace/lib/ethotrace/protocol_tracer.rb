# frozen_string_literal: true

module Ethotrace
  # 引数プロトコル観測の TracePoint エンジン。
  #
  # `TracePoint(:call)`(`:c_call` はオプトイン)で全メソッド呼び出しを監視し、
  # レシーバ(`tp.self`)が {ArgumentTable} に追跡登録された引数オブジェクトなら、
  # 呼ばれたメソッドを `(name, arity, block)` 粒度でその引数の所有コンテキストへ
  # 加算する({CallContext#record_protocol_call})。これにより「この引数に対して
  # 実際に呼ばれたメソッド集合(=プロトコル)」が観測される。
  #
  # 既定では `:call` のみを監視する。stdlib コアの多く(`Array#each` など)は C
  # 実装のため `:call` には現れず、`:c_call` をオプトインしたときのみ観測される
  # (高コストのため既定 OFF。ethotrace-design-handoff.md §4.1 / §11)。
  #
  # ハンドラは追跡テーブルが空(観測中の引数なし)なら即座に return する高速パスを
  # 持ち、被観測メソッドの実行中以外はほぼ無視できるコストに抑える。
  module ProtocolTracer
    module_function

    # TracePoint を有効化する。既に有効なら何もしない。
    #
    # @param trace_c_call [Boolean] C メソッド呼び出し(`:c_call`)も監視するか。
    def enable(trace_c_call: false)
      return if @tracepoint

      events = trace_c_call ? %i[call c_call] : %i[call]
      @tracepoint = TracePoint.new(*events) { |tp| handle(tp) }
      @tracepoint.enable
      nil
    end

    # TracePoint を無効化する。有効でなければ何もしない。
    def disable
      @tracepoint&.disable
      @tracepoint = nil
    end

    # TracePoint が有効か。
    def enabled?
      !@tracepoint.nil?
    end

    # TracePoint イベント 1 件を処理する。
    #
    # TracePoint のコールバックは同スレッドで非リエントラント(ハンドラ内の
    # メソッド呼び出しでは再発火しない)。加えてトレーサ内部処理中
    # ({ReentryGuard})のイベントは無視する。
    def handle(tracepoint)
      return if ReentryGuard.in_tracer?

      table = ArgumentTable.table
      return if table.empty?

      owners = table[ArgumentTable.object_id_of(tracepoint.self)]
      return if owners.nil? || owners.empty?

      record(tracepoint, owners)
    end

    # 呼ばれたメソッドを所有コンテキスト群のプロトコルへ加算する。
    def record(tracepoint, owners)
      name = tracepoint.callee_id.to_s
      arity, block = protocol_grain(tracepoint)
      owners.each do |context, position|
        context.record_protocol_call(position, name, arity: arity, block: block)
      end
      nil
    end

    # 呼び出しの粒度 `[arity, block]` を求める。binding を取得できない C 呼び出し
    # (`:c_call`)では `[0, false]` に近似する(v1 の割り切り)。
    def protocol_grain(tracepoint)
      binding = tracepoint.binding
      return [0, false] if binding.nil?

      [positional_arity(tracepoint, binding), block_passed?(tracepoint, binding)]
    end

    # メソッドが受け取った位置引数の実効数を数える。`opt` は既定値適用済みでも
    # カウントし、`rest` は実配列長を加える(呼び出し側が渡した個数の近似)。
    def positional_arity(tracepoint, binding)
      tracepoint.parameters.sum do |kind, name|
        case kind
        when :req, :opt then 1
        when :rest then rest_size(binding, name)
        else 0
        end
      end
    rescue StandardError
      0
    end

    # `*rest` パラメータに実際にバインドされた要素数。匿名 rest は数えられない。
    def rest_size(binding, name)
      return 0 if name.nil?

      value = binding.local_variable_get(name)
      value.is_a?(Array) ? value.size : 0
    rescue StandardError
      0
    end

    # 明示的なブロックパラメータ(`&blk`)に non-nil がバインドされたか。
    # ブロックパラメータを宣言しないメソッドへのブロック渡しは検出できない
    # (v1 の制約)。
    def block_passed?(tracepoint, binding)
      entry = tracepoint.parameters.find { |kind, _| kind == :block }
      name = entry && entry[1]
      return false if name.nil?

      !binding.local_variable_get(name).nil?
    rescue StandardError
      false
    end
  end
end
