# frozen_string_literal: true

# 検証用サンプルの spec_helper。
#
# ethotrace の計装(観測対象の prepend ラッパー + Requirements フック + 引数
# プロトコルの TracePoint)を「スイートで一度だけ」有効化し、観測結果の書き出し先
# (JSONL writer)だけを **spec ファイル(= 各レベル)ごと** に差し替える。こうすると
# 同じクラスを再 wrap せず(二重化を回避)、spec/ の横の result/ にレベル単位の JSONL を
# 得られる(result/level1_gate_spec.jsonl / level2_pricing_spec.jsonl / level3_dispatcher_spec.jsonl)。

require "ethotrace/rspec"
require "fileutils"

lib = File.expand_path("../lib", __dir__)
require "#{lib}/level1_gate"
require "#{lib}/level2_pricing"
require "#{lib}/level3_dispatcher"

Dir[File.expand_path("support/**/*.rb", __dir__)].sort.each { |f| require f }

# 観測結果の出力先(spec/ の横の result/)と、パス正規化の基準(リポジトリルート)。
RESULT_DIR = File.expand_path("../result", __dir__)
REPO_ROOT = File.expand_path("../../..", __dir__)

# 計装をスイートで一度だけ設置し、writer を spec ファイルごとに購読/解除する仕掛け。
module EthotracePerFile
  # 観測対象。methods: nil は当該クラス自身に定義された instance メソッド全部。
  TARGETS = [
    Ethotrace::RSpec::Target.new(klass: Gate, method_names: nil, kind: :instance),
    Ethotrace::RSpec::Target.new(klass: Pricing, method_names: nil, kind: :instance),
    Ethotrace::RSpec::Target.new(klass: Dispatcher, method_names: nil, kind: :instance),
    Ethotrace::RSpec::Target.new(klass: Ledger, method_names: nil, kind: :instance)
  ].freeze

  @writers = {} # absolute_file_path => { writer:, count: }
  @outputs = [] # 書き出した JSONL の出力パス(後でパス正規化する)

  class << self
    # スイート開始: アダプタ登録・計装・引数プロトコル観測を一度だけ有効化する。
    def install
      [Ethotrace::Adapters::Stdlib.new, Ethotrace::RSpec::TargetAdapter.new(TARGETS)]
        .each { |adapter| Ethotrace::AdapterRegistry.register(adapter) }
      Ethotrace::AdapterRegistry.install
      Ethotrace::ProtocolTracer.enable(trace_c_call: false)
    end

    # スイート終了: 計装とプロトコル観測を解除し、グローバルなレジストリを掃除する。
    # 公開サンプルとして成果物をコミットするため、site.path 等に入るリポジトリルートの
    # 絶対パスをリポジトリ相対へ正規化する(ユーザー名露出を避け、再実行で同じ結果にする)。
    def uninstall
      Ethotrace::AdapterRegistry.uninstall
      Ethotrace::ProtocolTracer.disable
      Ethotrace::AdapterRegistry.reset!
      normalize_paths
    end

    # spec ファイルの観測開始: そのファイル用の writer を(無ければ作って)購読する。
    # 1 ファイルに複数のトップレベル describe があっても 1 つの JSONL にまとめる。
    def open(group)
      path = group.metadata[:absolute_file_path]
      entry = (@writers[path] ||= start_writer(path))
      entry[:count] += 1
    end

    # spec ファイルの観測終了: そのファイルのトップレベル describe をすべて抜けたら
    # writer を購読解除して閉じる。
    def close(group)
      path = group.metadata[:absolute_file_path]
      entry = @writers[path] or return

      entry[:count] -= 1
      return if entry[:count].positive?

      Ethotrace::Wrapper.unsubscribe(entry[:writer])
      entry[:writer].close
      @writers.delete(path)
    end

    # トップレベルの example group(= spec ファイル直下の describe)か。
    def top_level?(group)
      group.metadata[:parent_example_group].nil?
    end

    private

    def start_writer(path)
      FileUtils.mkdir_p(RESULT_DIR)
      session = File.basename(path, ".rb") # 例: level1_gate_spec
      output = File.join(RESULT_DIR, "#{session}.jsonl")
      @outputs << output
      io = File.open(output, "w")
      io.sync = true
      writer = Ethotrace::JSONLWriter.new(
        io,
        session: session,
        adapters: Ethotrace::AdapterRegistry.names,
        options: {}
      )
      Ethotrace::Wrapper.subscribe(writer)
      { writer: writer, count: 0 }
    end

    # 出力 JSONL 内のリポジトリルート絶対パスをリポジトリ相対へ書き換える。
    def normalize_paths
      prefix = "#{REPO_ROOT}/"
      @outputs.uniq.each do |file|
        File.write(file, File.read(file).gsub(prefix, ""))
      end
      @outputs.clear
    end
  end
end

RSpec.configure do |config|
  config.expect_with(:rspec) { |c| c.syntax = :expect }

  config.before(:suite) { EthotracePerFile.install }
  config.after(:suite) { EthotracePerFile.uninstall }

  config.before(:context) { EthotracePerFile.open(self.class) if EthotracePerFile.top_level?(self.class) }
  config.after(:context) { EthotracePerFile.close(self.class) if EthotracePerFile.top_level?(self.class) }
end
