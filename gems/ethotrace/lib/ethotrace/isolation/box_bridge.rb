# frozen_string_literal: true

module Ethotrace
  module Isolation
    # box 内(probe 側)に常駐するブリッジ。{Isolation::Box} 戦略が root から
    # `box.eval` 経由で呼び、box 空間で probe(prepend フック)の設置と、root の
    # sink への配線を行う。
    #
    # 設計の要(box-semantics.md):
    # - probe(Wrapper / アダプタの prepend フック)は box 内のクラス実体に張る必要がある(E5)。
    #   よって install は **box 空間で実行**しなければならず、root のアダプタ実体を
    #   そのまま呼んでも root 側に張ってしまう(メソッド解決は所属空間に従う, E3)。
    #   このモジュールが box 空間側の install エントリになる。
    # - box 内 probe が組み立てた完了 {CallContext} は観測データを丸ごと運ぶため、
    #   box 内 {Collector} に **root の sink へ橋渡しする購読者** を 1 つ繋げば、
    #   観測データが root の JSONL ライターまで届く({Collector} のクラスコメント参照)。
    #
    # このモジュールは Ruby::Box に一切依存しない純粋な box 内グルーであり、root 空間で
    # ロードされても無害(未使用のまま)。Box が使えない環境の core を汚さない。
    module BoxBridge
      @adapters = []
      @sink = nil

      class << self
        # root の sink(完了 {CallContext} を受け取る callable)を box 内 {Collector} に繋ぐ。
        # sink は root のオブジェクトであり、その `call` は root 空間で実行される(E3)ため、
        # box の CallContext は root 側 Collector・JSONL ライターまで運ばれる。
        # @param root_sink [#call] root 側 sink。
        def connect(root_sink)
          @sink = root_sink
          Collector.subscribe(root_sink)
        end

        # box 空間で対象メソッドに観測ラッパーを設置する。root と同名のクラスでも
        # box 内では別実体であり、ここで張るフックは box 内呼び出しだけを捉える。
        # 自己適用(feature 5)で box 内の Ethotrace 自身のメソッドを wrap するのに使う。
        # @return [Boolean] 新たに計装したら true、計装済みなら false。
        def wrap(class_name, method, kind: :instance)
          Instrumenter.new.wrap_method(resolve(class_name), method, kind: kind)
        end

        # box 空間でアダプタ群を登録・install する。`class_names` は root 側で有効な
        # アダプタと同名のクラス(box 内の別実体)を解決して使う。
        # @param class_names [Array<String>] アダプタクラスの完全修飾名。
        def install_adapters(class_names)
          instrumenter = Instrumenter.new
          class_names.each do |name|
            adapter = resolve(name).new
            @adapters << adapter
            adapter.install(instrumenter)
          end
        end

        # box 空間で probe を解除し、root sink の購読を外す。
        def disconnect
          instrumenter = Instrumenter.new
          @adapters.each { |adapter| adapter.uninstall(instrumenter) }
          @adapters = []
          Collector.unsubscribe(@sink) if @sink
          @sink = nil
        end

        # 状態を初期化する(主にテスト用)。フックの実体解除は伴わない。
        def reset!
          @adapters = []
          @sink = nil
        end

        private

        # 完全修飾名から box 空間のクラス実体を解決する。
        def resolve(name)
          name.to_s.split("::").inject(Object) { |mod, const| mod.const_get(const) }
        end
      end
    end
  end
end
