# frozen_string_literal: true

module Ethotrace
  # 計装の物理機構: 横取りモジュールの生成・prepend・記述子の算出。
  #
  # 「どのメソッドを計装するか」(語彙・対象選択)は持たず、prepend という
  # 仕組みだけを提供する低レベル層。生成したラッパーは実行時に
  # {Wrapper.observe} を呼んで三チャネル観測へ橋渡しする。
  #
  # 注: これは core 内部の機構であり、M2 でアダプタへ公開する `instrumenter`
  # API(`wrap_method` 等)とは層が異なる。
  module Instrumentation
    module_function

    # klass の name(kind 種別)に横取りモジュールを prepend する。
    #
    # @return [Hash] begin_call へ渡す記述子(owner/name/kind/site)。
    def install(klass, name, kind)
      target = prepend_target(klass, kind)
      descriptor = descriptor_for(klass, target, name, kind)
      param_names = positional_param_names(target.instance_method(name))
      mod = Module.new
      mod.define_method(name) do |*args, **kw, &blk|
        Ethotrace::Wrapper.observe(descriptor, args, param_names) { super(*args, **kw, &blk) }
      end
      apply_visibility(mod, target, name)
      target.prepend(mod)
      descriptor
    end

    # 計装対象(prepend 先): インスタンスは klass 自身、特異は特異クラス。
    def prepend_target(klass, kind)
      kind == :singleton ? klass.singleton_class : klass
    end

    # begin_call へ渡す記述子を組み立てる。
    def descriptor_for(klass, target, name, kind)
      {
        owner: owner_name(klass),
        name: name,
        kind: kind,
        site: site_of(target.instance_method(name))
      }
    end

    # 位置引数(position 0 起点)に対応する仮引数名を定義順に返す。引数プロトコル
    # 観測で position と name を結びつけるために使う。`*rest` を超えた位置や匿名
    # 引数の name は nil になる(position は ArgumentTable 側で補う)。
    def positional_param_names(unbound)
      unbound.parameters.filter_map do |kind, pname|
        pname if %i[req opt].include?(kind)
      end
    end

    # 元メソッドの可視性(private/protected)をラッパー側へ複製する。
    # public は define_method の既定なので何もしない。
    def apply_visibility(mod, target, name)
      if target.private_method_defined?(name)
        mod.send(:private, name)
      elsif target.protected_method_defined?(name)
        mod.send(:protected, name)
      end
    end

    # 完全修飾名。無名クラス/モジュールは to_s で表す。
    def owner_name(klass)
      klass.name || klass.to_s
    end

    # 定義位置を { path:, line: } へ整形する。C 実装など取得不能なら nil。
    def site_of(unbound)
      path, line = unbound.source_location
      return nil if path.nil?

      { path: path, line: line }
    end
  end
end
