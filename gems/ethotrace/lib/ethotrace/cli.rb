# frozen_string_literal: true

require_relative "../ethotrace"
require_relative "cli/color"
require_relative "cli/reader"
require_relative "cli/aggregator"
require_relative "cli/renderer"
require_relative "cli/view_command"

module Ethotrace
  # `ethotrace` 実行ファイルのコマンドディスパッチャ。
  #
  # 観測結果 JSONL を消費する開発者向けツール群の入口。現状は `view`
  # (ターミナルでの簡易ビューア)を提供する。
  module CLI
    module_function

    # @param argv [Array<String>]
    # @return [Integer] 終了ステータス。
    def start(argv, out: $stdout, err: $stderr)
      command, *rest = argv
      case command
      when "view" then ViewCommand.new(out: out, err: err).run(rest)
      when "-v", "--version" then print_line(out, VERSION)
      when nil, "-h", "--help", "help" then print_line(out, usage)
      else unknown(command, out, err)
      end
    end

    def print_line(io, text)
      io.puts(text)
      0
    end

    def unknown(command, _out, err)
      err.puts("ethotrace: unknown command: #{command}")
      err.puts(usage)
      1
    end

    def usage
      <<~USAGE
        Usage: ethotrace <command> [options]

        Commands:
          view <file.jsonl>...   観測結果 JSONL をターミナルで表示する
          help                   このヘルプを表示する

        Options:
          -v, --version          バージョンを表示する
      USAGE
    end
  end
end
