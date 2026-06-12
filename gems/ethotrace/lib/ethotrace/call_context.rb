# frozen_string_literal: true

module Ethotrace
  # 1 回のメソッド呼び出しに対応する観測アキュムレータ。
  #
  # prepend ラッパーが呼び出しの開始時に 1 つ生成し、呼び出しスコープの中で
  # 三チャネル(Success / Error / Requirements)+ 引数プロトコルの観測結果を
  # 蓄積する。Success(戻り値)/ Error(エスケープ例外)/ Requirements
  # (エフェクト)に加え、M3 で引数プロトコル(params)を埋める。引数プロトコルは
  # TracePoint エンジンが {record_protocol_call} 経由で加算する。
  #
  # CallContext は「何を観測したか」だけを保持し、コールスタックや帰属
  # (direct / inherited の判定)は Tracker 側が担う。owner/name/kind/site は
  # 計装時に確定する記述子として外から受け取る。
  class CallContext
    # メソッド記述子。
    attr_reader :owner, :name, :kind, :site

    # @param owner [String] メソッドを定義するクラス/モジュールの完全修飾名。
    # @param name [String, Symbol] メソッド名。
    # @param kind [Symbol, String] :instance / :singleton。
    # @param site [Hash, nil] 定義位置 `{ path:, line: }`。観測不能なら nil。
    def initialize(owner:, name:, kind:, site: nil)
      @owner = owner.to_s
      @name = name.to_s
      @kind = kind.to_sym
      @site = site
      # Success チャネル: 戻り値として観測されたクラス名集合(単一呼び出しでも
      # 和集合として扱い、重複は持たない)。
      @return_classes = []
      # Error チャネル: メソッド外へエスケープした例外のエントリ集合。
      @escaped_errors = []
      # Requirements チャネル: 外部世界への接触(エフェクト)のエントリ集合。
      @requirements = []
      # 引数プロトコル: position => { position:, name:, protocol:, classes_seen: }。
      # begin_call 時に各実引数が {record_argument} で登録され、TracePoint
      # エンジンが {record_protocol_call} でプロトコルを加算する。
      @params = {}
    end

    # 引数プロトコル: 実引数を 1 つ登録する。
    #
    # 計装側(prepend ラッパー)が呼び出し開始時に各実引数について呼び、
    # classes_seen(観測された実クラス)を蓄積する。追跡テーブルはここで
    # 登録された引数の object_id のみをプロトコル観測の対象にする。
    #
    # @param position [Integer] 引数位置(0 起点)。
    # @param value [Object] 実引数オブジェクト。
    # @param name [String, Symbol, nil] 仮引数名(取得できる場合)。
    def record_argument(position, value, name: nil)
      slot = param_slot(position, name)
      class_name = class_name_of(value)
      slot[:classes_seen] << class_name if class_name && !slot[:classes_seen].include?(class_name)
      nil
    end

    # 引数プロトコル: 引数オブジェクトに対して観測されたメソッド呼び出しを記録する。
    #
    # TracePoint エンジン(feature/tracepoint-engine)が `tp.self` の突き合わせを
    # 経て呼ぶ。v1 の粒度は `(name, arity, block)`。同一エントリは重複排除する。
    #
    # @param position [Integer] 引数位置(0 起点)。
    # @param name [String, Symbol] 呼ばれたメソッド名。
    # @param arity [Integer] 渡された実引数の個数。
    # @param block [Boolean] ブロックが渡されたか。
    def record_protocol_call(position, name, arity:, block:)
      slot = param_slot(position, nil)
      entry = { name: name.to_s, arity: arity, block: block }
      slot[:protocol] << entry unless slot[:protocol].include?(entry)
      nil
    end

    # Success チャネル: 戻り値を記録し、その値をそのまま返す。
    #
    # ラッパーが `result = super(...); ctx.record_return(result); result` と
    # 書けるよう、引数をそのまま返す。匿名クラス(name が nil)は記録しない。
    def record_return(value)
      class_name = class_name_of(value)
      @return_classes << class_name if class_name && !@return_classes.include?(class_name)
      value
    end

    # Error チャネル: メソッド外へエスケープした例外を記録する。
    #
    # origin / from は帰属(feature/error-attribution)が供給する。単独では
    # 当該メソッド自身で発生した例外として "direct" 既定で記録する。
    #
    # @param exception [Exception] エスケープした例外。
    # @param origin [String] "direct"(当該メソッド発生)/ "inherited"(callee から伝播)。
    # @param from [String, nil] inherited の場合の伝播元メソッド(`Owner#name` 形式)。
    def record_escaped_exception(exception, origin: "direct", from: nil)
      class_name = class_name_of(exception)
      return if class_name.nil?

      entry = { class: class_name, origin: origin, from: from }
      @escaped_errors << entry unless @escaped_errors.include?(entry)
    end

    # Requirements チャネル: 外部世界への接触(エフェクト)を記録する。
    #
    # direct / from は帰属(Tracker.record_effect)が供給する。同一エフェクトが
    # 1 呼び出し中に複数回発火しても観測集合としては 1 件に重複排除する。
    #
    # @param kind [String, Symbol] エフェクト語彙(例: "env.read")。
    # @param write [Boolean] 書き込み系(副作用的)か読み取り系(要件的)か。
    # @param direct [Boolean] 当該メソッド自身での発火か、callee からの継承か。
    # @param from [String, nil] 継承元メソッド(`Owner#name` 形式)。
    # @param detail [Hash] エフェクト固有の詳細(機微情報は含めない)。
    def add_requirement(kind, write:, direct:, from: nil, detail: {})
      entry = { kind: kind.to_s, write: write, direct: direct, from: from, detail: detail }
      @requirements << entry unless @requirements.include?(entry)
    end

    # この呼び出し 1 件分の method_observation レコードを構築する。
    #
    # session / captured_at は観測コンテキストを知る JSONL ライターが付与する
    # ため、ここでは含めない。params / requirements は後続マイルストーンで
    # 埋めるため、スキーマ形状を保つ目的で空配列を置く。
    def to_observation
      {
        schema_version: SCHEMA_VERSION,
        type: "method_observation",
        method: { owner: @owner, name: @name, kind: @kind.to_s },
        site: @site,
        **observed_channels
      }
    end

    private

    # 蓄積された観測チャネル。固定メタデータと分け、可変部だけをまとめる。
    def observed_channels
      {
        params: build_params,
        return: { classes_seen: @return_classes.dup },
        errors: @escaped_errors.map(&:dup),
        requirements: @requirements.map(&:dup),
        samples: 1
      }
    end

    # position に対応する引数スロットを取得(なければ生成)する。仮引数名は
    # 最初に得られた非 nil の値を保持する(TracePoint 側からは nil で来るため)。
    def param_slot(position, name)
      slot = (@params[position] ||= { position: position, name: nil, protocol: [], classes_seen: [] })
      slot[:name] ||= name&.to_s
      slot
    end

    # params 配列を position 昇順で構築する。内部蓄積を破壊しないよう複製する。
    def build_params
      @params.keys.sort.map do |position|
        slot = @params[position]
        {
          position: slot[:position],
          name: slot[:name],
          protocol: slot[:protocol].map(&:dup),
          classes_seen: slot[:classes_seen].dup
        }
      end
    end

    # 対象オブジェクト本来のクラス名を得る。
    #
    # 観測対象が `class` を独自定義していても欺かれないよう、Object 由来の
    # UnboundMethod を束ねて取得する。Kernel を include しない純粋な
    # BasicObject などクラスを得られない値では nil を返す。
    def class_name_of(object)
      CLASS_METHOD.bind_call(object).name
    rescue StandardError
      nil
    end

    # `Object#class`(実体は Kernel#class)の UnboundMethod。
    CLASS_METHOD = ::Object.instance_method(:class)
    private_constant :CLASS_METHOD
  end
end
