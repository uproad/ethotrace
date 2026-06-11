# frozen_string_literal: true

module Ethotrace
  # 1 回のメソッド呼び出しに対応する観測アキュムレータ。
  #
  # prepend ラッパーが呼び出しの開始時に 1 つ生成し、呼び出しスコープの中で
  # 三チャネル(Success / Error / Requirements)+ 引数プロトコルの観測結果を
  # 蓄積する。M1 では Success(戻り値)と Error(エスケープ例外)のみを扱い、
  # params / requirements は後続マイルストーンで埋める(到達するまでは空配列)。
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
    # params / requirements は後続マイルストーンが埋めるまで空配列を置く。
    def observed_channels
      {
        params: [],
        return: { classes_seen: @return_classes.dup },
        errors: @escaped_errors.map(&:dup),
        requirements: [],
        samples: 1
      }
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
