# frozen_string_literal: true

module Ethotrace
  # 1 回の観測セッション(= テストワーカー単位)を束ねるオーケストレーション。
  #
  # アダプタの登録・計装({AdapterRegistry})、観測結果を書き出す
  # {JSONLWriter} の購読、セッションライフサイクル通知をまとめる。テスト
  # アダプタ(ethotrace-rspec / -minitest)や利用者が {start} … {#finish} で
  # 囲って使う。既定では core 内蔵の stdlib アダプタを有効化する。
  #
  # 並列実行ではワーカーごとに別ファイル・別セッション ID を割り当てる(id は
  # 呼び出し側が一意化する。既定は PID ベース)。
  class Session
    attr_reader :id

    # 観測セッションを開始する。
    #
    # アダプタを登録・計装し、`io` へ書き出す {JSONLWriter} を {Wrapper} の
    # 購読者に登録して、session レコード(adapters 名・options)を出力する。
    #
    # @param io [IO] 観測結果 JSONL の出力先。
    # @param id [String] セッション識別子(並列実行で一意化)。
    # @param adapters [Array<Adapter>, nil] 有効化するアダプタ(nil なら stdlib のみ)。
    # @param options [Hash] 観測オプション(trace_c_call / record_sql_source 等)。
    # @param isolation [Isolation::Strategy] probe の設置先を決める隔離戦略
    #   (既定は {Isolation::Null} = probe・collector 同一空間)。
    # @return [Session]
    def self.start(io, id: "ethotrace-pid#{Process.pid}", adapters: nil, options: {}, isolation: Isolation::Null.new)
      (adapters || [Adapters::Stdlib.new]).each { |adapter| AdapterRegistry.register(adapter) }
      # probe(アダプタの prepend フック)の設置先は隔離戦略に委ねる。
      isolation.install_probe(AdapterRegistry)
      writer = JSONLWriter.new(io, session: id, adapters: AdapterRegistry.names, options: options)
      # collector 側: 観測の sink は常に root(同一プロセス)で購読する。
      Collector.subscribe(writer)
      # 引数プロトコル観測の TracePoint は root 側で有効化する(box を越境して観測可。
      # :c_call はオプトイン)。隔離戦略によらず常に root。
      ProtocolTracer.enable(trace_c_call: options.fetch(:trace_c_call, false))
      AdapterRegistry.start_session(id)
      new(id: id, writer: writer, isolation: isolation)
    end

    def initialize(id:, writer:, isolation:)
      @id = id
      @writer = writer
      @isolation = isolation
    end

    # 観測セッションを終了する。アダプタへ終了を通知し、計装を無効化して、
    # 購読を解除し、出力先を閉じる。probe の解除は隔離戦略に委ねる。
    def finish
      AdapterRegistry.end_session(@id)
      @isolation.uninstall_probe(AdapterRegistry)
      ProtocolTracer.disable
      Collector.unsubscribe(@writer)
      @writer.close
    end
  end
end
