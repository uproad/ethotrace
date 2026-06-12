# frozen_string_literal: true

require "optparse"
require "json"
require "fileutils"

module Ethotrace
  module CLI
    # `ethotrace merge` サブコマンド。
    #
    # 並列テストワーカーが吐いた複数の JSONL(`tmp/ethotrace/<session>.jsonl`)を
    # 読み、{Ethotrace::Merge} の正規マージ意味論で統合して、observations.jsonl を
    # 書き出す。出力は入力と同じ method_observation 形を 1 行 1 レコードで保つため、
    # 後から追記・再マージ可能(docs/schema.md §7)。
    #
    # 標準出力はパイプできるよう**純粋な JSONL のみ**を流し、進捗・警告・サマリは
    # 標準エラーへ出す。`-o` 省略時は標準出力へ書く。
    class MergeCommand
      def initialize(out: $stdout, err: $stderr)
        @out = out
        @err = err
      end

      # @return [Integer] 終了ステータス。
      def run(argv)
        options = {}
        files = expand(parse(argv, options))
        return 0 if options[:help]
        return usage_error("no input files") if files.empty?

        merged = Merge.call(Reader.new(warn_io: @err).read(files).observations)
        write(merged, options[:output])
        report(merged, files, options[:output])
        0
      rescue OptionParser::ParseError => e
        usage_error(e.message)
      end

      private

      def parse(argv, options)
        parser = build_parser(options)
        files = parser.parse(argv)
        @out.puts(parser) if options[:help]
        files
      end

      def build_parser(options)
        OptionParser.new do |o|
          o.banner = "Usage: ethotrace merge [options] <file.jsonl>..."
          o.on("-o", "--output PATH", "write merged JSONL to PATH (default: stdout)") { |v| options[:output] = v }
          o.on("-h", "--help", "show this help") { options[:help] = true }
        end
      end

      # シェルが展開しなかった glob パターン(クォートされた `*.jsonl` 等)を
      # 自前で展開する。マッチしない引数はそのまま残し、Reader 側で
      # 「no such file」警告に委ねる。
      def expand(args)
        args.flat_map do |arg|
          matches = Dir.glob(arg)
          matches.empty? ? [arg] : matches.sort
        end
      end

      def write(merged, output)
        lines = merged.map { |record| JSON.generate(record) }
        if output
          FileUtils.mkdir_p(File.dirname(output))
          File.write(output, lines.map { |line| "#{line}\n" }.join)
        else
          lines.each { |line| @out.puts(line) }
        end
      end

      def report(merged, files, output)
        sessions = merged.flat_map { |record| record[:sessions] }.uniq.size
        destination = output || "stdout"
        @err.puts("[ethotrace] merged #{merged.size} observations from " \
                  "#{sessions} session(s) across #{files.size} file(s) -> #{destination}")
      end

      def usage_error(message)
        @err.puts("ethotrace merge: #{message}")
        1
      end
    end
  end
end
