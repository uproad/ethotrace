# frozen_string_literal: true

module Ethotrace
  # 引数プロトコル観測のための object_id 追跡テーブル(Thread/Fiber-local)。
  #
  # 呼び出し開始時に各実引数の object_id を「どの {CallContext} の第何引数か」で
  # 登録し、TracePoint エンジンが `tp.self` の object_id と突き合わせて引数
  # プロトコルを帰属できるようにする。呼び出し終了時({Tracker.end_call})に必ず
  # 掃除する(GC 後の object_id 再利用対策。ethotrace-design-handoff.md §4.3)。
  #
  # {Tracker} とはライフサイクルを共有するが、コールスタック管理・帰属とは別の
  # 関心事なので独立モジュールに分離する。
  module ArgumentTable
    # object_id => [[context, position], ...]。同一オブジェクトが複数の活性
    # コンテキストの引数になりうる(callee へ素通しされる)ため複数所有を許す。
    TABLE_KEY = :ethotrace_arg_table
    # 各コンテキストが登録した object_id の逆引き(context => [object_id, ...])。
    # 掃除を O(登録引数数) に保ち、テーブル全走査を避ける。
    TRACKED_IDS_KEY = :ethotrace_tracked_ids

    module_function

    # context の実引数を登録する。
    #
    # 各実引数について classes_seen を記録({CallContext#record_argument})しつつ、
    # 追跡対象オブジェクトは object_id をテーブルへ載せる。値共有 immediate
    # (Integer / Symbol / Float / true / false / nil)は object_id が値で共有され
    # `tp.self` と誤マッチするため、classes_seen は記録するが追跡テーブルには
    # 載せない(v1 の割り切り)。
    #
    # @param context [CallContext] 引数を所有する呼び出しコンテキスト。
    # @param values [Array] 位置引数の値(position 0 起点)。
    # @param names [Array<String, Symbol, nil>] 対応する仮引数名(取得できる場合)。
    def track(context, values, names = [])
      values.each_with_index do |value, position|
        context.record_argument(position, value, name: names[position])
        next unless trackable?(value)

        id = object_id_of(value)
        next if id.nil?

        (table[id] ||= []) << [context, position]
        (tracked_ids[context] ||= []) << id
      end
      nil
    end

    # object_id の所有者一覧 `[[context, position], ...]` を引く。未登録なら空配列。
    def lookup(object_id)
      table[object_id] || []
    end

    # context が登録した全 object_id をテーブルから取り除く。
    def untrack(context)
      ids = tracked_ids.delete(context)
      return if ids.nil?

      ids.each do |id|
        entries = table[id]
        next if entries.nil?

        entries.reject! { |ctx, _position| ctx.equal?(context) }
        table.delete(id) if entries.empty?
      end
      nil
    end

    # 現在の Thread/Fiber のテーブルと逆引きを破棄する(セッション境界やテスト用)。
    def reset
      Thread.current[TABLE_KEY] = nil
      Thread.current[TRACKED_IDS_KEY] = nil
    end

    # 現在の Thread/Fiber の追跡テーブル(object_id => [[context, position]])。
    def table
      Thread.current[TABLE_KEY] ||= {}
    end

    # 現在の Thread/Fiber の逆引き(context => 登録した object_id 群)。
    # コンテキストは同一性で識別する(eql? の独自定義に欺かれないため)。
    def tracked_ids
      Thread.current[TRACKED_IDS_KEY] ||= {}.compare_by_identity
    end

    # 引数オブジェクトの object_id を安全に得る。object_id を持たない値
    # (BasicObject 派生など)では nil を返し、追跡対象から外す。
    def object_id_of(value)
      OBJECT_ID_METHOD.bind_call(value)
    rescue StandardError
      nil
    end

    # 値共有 immediate を追跡対象から除外する判定。これらは object_id が値で
    # 共有され、無関係な同値オブジェクトの呼び出しを誤帰属してしまう。
    def trackable?(value)
      case value
      when Integer, Symbol, Float, true, false, nil then false
      else true
      end
    end

    # `Object#object_id`(独自定義に欺かれないよう束縛して使う)の UnboundMethod。
    OBJECT_ID_METHOD = ::Object.instance_method(:object_id)
    private_constant :OBJECT_ID_METHOD
  end
end
