# frozen_string_literal: true

module Ethotrace
  module Isolation
    # Ruby::Box(Ruby 4.0 experimental)による実体分離戦略。probe(prepend フック +
    # box 内 Ethotrace)を子 box に閉じ込め、観測イベントだけを root の {Collector} へ
    # 橋渡しする。観測者と観測対象が同一クラス実体を共有して汚染する自己適用問題を、
    # box 内 `Ethotrace::Tracker` が root と別実体になることで構造的に解く(box-semantics.md / 設計資料 §4.8)。
    #
    # 構成:
    #   root(collector)              box(probe)
    #   - root Collector / Writer ◀── BoxBridge.connect(root_sink)
    #                                - box Ethotrace(別実体)
    #                                - box 内クラスへの prepend フック
    #
    # 適用条件と制約(experimental):
    # - Ruby >= 4.0 かつ `RUBY_BOX=1`({.available?})。満たさなければ {#install_probe} で
    #   {Ethotrace::Error} を送出する。呼び出し側は {.available?} で {Null} へフォールバックする。
    # - **main box から起動**すること。既に Ethotrace をロード済みの非 main box(例:
    #   `RUBY_BOX=1 bundle exec rspec` の root box)から作った子 box は親定義を**共有**し、
    #   分離が成立しない(box-semantics.md「box 系譜とロード順への依存」)。自己適用 E2E は
    #   スタンドアロンの `RUBY_BOX=1 ruby` 起動を前提とする。
    #
    # box 内グルーは {BoxBridge}。root からは `@box.eval("...BoxBridge").<op>` で box 空間の
    # install/uninstall を駆動する(メソッド解決の所属空間に従わせるため, E3)。
    class Box < Strategy
      # core の lib ディレクトリ(box の load_path に通して box 内へ Ethotrace を新規ロードする)。
      DEFAULT_LIB_PATH = File.expand_path("../..", __dir__)

      # root 側 sink。box 内 {Collector} へ購読させ、完了 {CallContext} を root の
      # {Collector} へ転送する。`#call` は root 空間で実行される(E3)ため、ここで
      # 参照する `Collector` は root の実体になり、観測データが root の JSONL ライターへ届く。
      class RootSink
        def call(context)
          Collector.publish(context)
        end
      end

      # Ruby::Box が利用可能か(Ruby >= 4.0 かつ RUBY_BOX=1)。
      def self.available?
        defined?(::Ruby::Box) && ::Ruby::Box.enabled?
      end

      # @param lib_path [String] box の load_path に通す core lib のパス(注入可能)。
      def initialize(lib_path: DEFAULT_LIB_PATH)
        super()
        @lib_path = lib_path
        @box = nil
      end

      # 生成した子 box(box 空間の対象 wrap 等に使う。未 install 時は nil)。
      attr_reader :box

      # 子 box を起て、box 内に Ethotrace を新規ロードして probe を設置する。
      # 観測イベントは root の {Collector} へ転送される。
      # @param registry [AdapterRegistry] box 内で同名アダプタを install する元。
      def install_probe(registry)
        ensure_available!
        @box = ::Ruby::Box.new
        @box.load_path.unshift(@lib_path)
        @box.require("ethotrace")
        bridge = @box.eval("Ethotrace::Isolation::BoxBridge")
        bridge.connect(RootSink.new)
        bridge.install_adapters(registry.adapters.map { |adapter| adapter.class.name })
      end

      # box 内 probe を解除し、box を破棄する。
      # @param registry [AdapterRegistry] 契約上の引数(box 側で解除するため未使用)。
      def uninstall_probe(_registry)
        return unless @box

        @box.eval("Ethotrace::Isolation::BoxBridge").disconnect
        @box = nil
      end

      private

      def ensure_available!
        return if self.class.available?

        raise Ethotrace::Error,
              "BoxIsolation requires Ruby >= 4.0 with RUBY_BOX=1 (Ruby::Box.enabled?). " \
              "Use Isolation::Null when Ruby::Box is unavailable."
      end
    end
  end
end
