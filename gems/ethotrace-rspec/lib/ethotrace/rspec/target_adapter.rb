# frozen_string_literal: true

require "ethotrace"

module Ethotrace
  module RSpec
    # 1 つの観測対象(クラス + メソッド集合 + kind)。
    #
    # method_names が nil のときは klass 自身に定義されたメソッド(継承分を除く)を
    # 列挙する。`(klass, name, kind)` の組へ展開して計装に渡す。メンバ名は
    # `Data#methods`(= Object#methods)の上書きを避けるため method_names とする。
    Target = Data.define(:klass, :method_names, :kind) do
      # 計装対象を `[name, kind]` の配列として返す。
      def method_specs
        names = method_names || own_methods
        names.map { |name| [name.to_sym, kind] }
      end

      private

      def own_methods
        kind == :singleton ? klass.singleton_methods(false) : klass.instance_methods(false)
      end
    end

    # ユーザーコードの観測対象を計装するアダプタ。
    #
    # core は「観測の物理学」、アダプタは「意味論(計装対象の選択)」を担う
    # という分担に従い、{Configuration#observe} で集めた対象を {Instrumenter}
    # 経由で wrap する。dogfooding 原則どおり公開 API({Instrumenter#wrap_method})
    # のみを使い、core の裏口は使わない。
    class TargetAdapter < Ethotrace::Adapter
      # @param targets [Array<Target>]
      def initialize(targets)
        super()
        @targets = targets
      end

      # session レコードに載る識別名。
      def name
        "rspec-targets"
      end

      # 各対象の各メソッドへ観測ラッパーを設置する。二重 wrap は Wrapper が防ぐ。
      def install(instrumenter)
        @targets.each do |target|
          target.method_specs.each do |method_name, kind|
            instrumenter.wrap_method(target.klass, method_name, kind: kind)
          end
        end
      end
    end
  end
end
