# frozen_string_literal: true

module Ethotrace
  # 隔離戦略(isolation strategy)。観測の **probe**(prepend ベースのフック設置)を
  # 「どの空間で」走らせるかを決める差し替え可能な方針。
  #
  # 設計の要(box-semantics.md の検証結果):
  # - **collector**(記録・帰属・JSONL)は常に root に置き、probe からイベントを受ける。
  # - **プロトコル観測の TracePoint** は root 側のままで box を越境して観測できる(E1)。
  #   よって TracePoint は戦略によって変わらず、Session が直接 enable/disable する。
  # - **Requirements / Success・Error の prepend フック**だけは観測対象と同じ空間に
  #   張る必要がある(E5)。この「probe をどこへ設置するか」が戦略ごとに変わる唯一の軸。
  #
  # したがって戦略の責務は probe(= アダプタ群の install/uninstall)の設置先制御に限る。
  #
  # 既定は {Null}(probe = collector 同一空間 = 従来の振る舞い)。Ruby::Box による
  # 実体分離 {Box}(M5 feature 4)や Ruby 3.x フォールバックの Stage0 ブートストラップは、
  # この {Strategy} を継承して `install_probe` / `uninstall_probe` を差し替える。
  module Isolation
    # 隔離戦略の契約(interface)。
    class Strategy
      # probe(アダプタ群の prepend フック)を設置する。
      # @param registry [AdapterRegistry] 設置対象のアダプタを保持するレジストリ。
      def install_probe(registry)
        raise NotImplementedError, "#{self.class} must implement #install_probe"
      end

      # probe を解除する。
      # @param registry [AdapterRegistry]
      def uninstall_probe(registry)
        raise NotImplementedError, "#{self.class} must implement #uninstall_probe"
      end
    end

    # 既定の隔離戦略。probe と collector が同一空間に同居する(隔離しない)。
    # 観測対象が Ethotrace 自身でない通常の解析はこれで足りる。
    #
    # box-semantics.md の用語では「probe = collector が同一空間にいる」縮退形であり、
    # 従来(隔離戦略導入前)の振る舞いをそのまま保つ。
    class Null < Strategy
      # 同一空間で既定の {Instrumenter} を使ってアダプタを install する。
      def install_probe(registry)
        registry.install
      end

      # 同一空間でアダプタを uninstall する。
      def uninstall_probe(registry)
        registry.uninstall
      end
    end
  end
end
