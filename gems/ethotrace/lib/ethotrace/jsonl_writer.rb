# frozen_string_literal: true

require "json"
require "time"
require "monitor"
require "fileutils"

module Ethotrace
  # 観測結果を JSON Lines として書き出すシンク。
  #
  # 生成時に `session` レコードを 1 行出力し、その後 {Collector.subscribe} の
  # 購読者として渡されると、完了した {CallContext} ごとに `method_observation`
  # レコードを 1 行追記する。スキーマは docs/schema.md(schema_version 1)が正。
  #
  # 1 行 = 1 JSON で追記可能・マージ可能。並列テストワーカーはワーカーごとに
  # 別ファイルへ書く(セッション ID で一意化)。同一プロセス内の複数スレッドが
  # 同じシンクへ流す場合に備え、書き込みはモニタで直列化する。
  #
  # 時刻・バージョン・セッション ID は注入可能にしており、ゴールデン比較を
  # 決定的にできる。
  class JSONLWriter
    # 観測オプションの既定値(schema §3 の `options`)。
    DEFAULT_OPTIONS = { trace_c_call: false, record_sql_source: false }.freeze

    # ファイルパスを開いてライターを生成する。ブロックを与えると、その終了時に
    # 自動で close する。
    def self.open(path, **)
      FileUtils.mkdir_p(File.dirname(path))
      # fd は生成したライターが寿命を通じて保持し、#close(またはブロック ensure)で
      # 閉じる。そのためブロック形は使わない。
      io = File.open(path, "a") # rubocop:disable Style/FileOpen
      io.sync = true
      writer = new(io, **)
      return writer unless block_given?

      begin
        yield writer
      ensure
        writer.close
      end
    end

    # @param io [IO] 出力先(File / StringIO 等)。
    # @param session [String] セッション識別子(並列実行で一意化する)。
    # @param adapters [Array<String>] 有効なアダプタ名。
    # @param options [Hash] 観測オプション。
    # @param ruby_version [String] 観測時の Ruby バージョン。
    # @param ethotrace_version [String] 観測に用いた core のバージョン。
    # @param clock [#call] 現在時刻を返す callable(注入可能)。
    def initialize(io, session:, adapters: [], options: DEFAULT_OPTIONS,
                   ruby_version: RUBY_VERSION, ethotrace_version: Ethotrace::VERSION,
                   clock: -> { Time.now })
      @io = io
      @session = session
      @adapters = adapters
      @options = DEFAULT_OPTIONS.merge(options)
      @ruby_version = ruby_version
      @ethotrace_version = ethotrace_version
      @clock = clock
      @lock = Monitor.new
      write_record(session_record)
    end

    # {Wrapper} 購読者インターフェース: 完了した CallContext を 1 行書き出す。
    def call(context)
      write_record(observation_record(context))
    end

    # 出力先を閉じる。複数回呼んでも安全。
    def close
      @lock.synchronize { @io.close unless @io.closed? }
    end

    # 出力先が閉じられているか。
    def closed?
      @io.closed?
    end

    private

    def session_record
      {
        schema_version: SCHEMA_VERSION,
        type: "session",
        session: @session,
        started_at: now,
        ruby_version: @ruby_version,
        ethotrace_version: @ethotrace_version,
        adapters: @adapters,
        options: @options
      }
    end

    # CallContext の観測へ、シンクが知るセッション文脈(session/captured_at)を付与する。
    def observation_record(context)
      context.to_observation.merge(session: @session, captured_at: now)
    end

    def now
      @clock.call.iso8601
    end

    def write_record(record)
      line = JSON.generate(record)
      @lock.synchronize do
        @io.puts(line)
        @io.flush if @io.respond_to?(:flush)
      end
    end
  end
end
