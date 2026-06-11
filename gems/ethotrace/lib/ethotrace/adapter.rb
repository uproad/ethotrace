# frozen_string_literal: true

module Ethotrace
  # アダプタの基底クラス(プラグイン契約)。
  #
  # core は「観測の物理学」、アダプタは「意味論」(計装対象の選択・エフェクト語彙の
  # 割り当て・テストライフサイクル接続)を担う。アダプタは {Instrumenter} を介して
  # のみ core を操作する(dogfooding 原則: core 内蔵の stdlib アダプタも同じ API を使う)。
  #
  # サブクラスは必要なフックだけを上書きする。既定はすべて no-op。
  # 詳細は ethotrace-design-handoff.md §5 を参照。
  class Adapter
    # session レコード(docs/schema.md §3 の `adapters`)に載る短い識別名。
    # 具象アダプタは "stdlib" のような短い名前を返すよう上書きする。
    def name
      self.class.name || self.class.to_s
    end

    # 計装フェーズ: チョークポイントへフックを登録する(プロセス単位)。
    def install(instrumenter); end

    # 計装の解除。
    def uninstall(instrumenter); end

    # ライフサイクル: セッション(=テストワーカー)開始。
    def on_session_start(session); end

    # ライフサイクル: セッション終了。
    def on_session_end(session); end
  end
end
