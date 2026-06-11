# frozen_string_literal: true

require "json"

module Ethotrace
  module CLI
    # 1 つ以上の JSONL ファイルを読み、レコードを種別ごとに仕分ける。
    #
    # 壊れた行は警告して読み飛ばす(さっと見る用途のため全体を止めない)。
    # 観測プロセスとは schema_version 付き JSONL でのみ結合する契約のため、
    # 未知/混在の schema_version は警告する(docs/schema.md §7)。
    class Reader
      Result = Data.define(:sessions, :observations, :schema_versions)

      def initialize(warn_io: $stderr)
        @warn_io = warn_io
      end

      # @param paths [Array<String>] 入力 JSONL のパス。
      # @return [Result]
      def read(paths)
        records = paths.flat_map { |path| records_in(path) }
        versions = records.filter_map { |record| record[:schema_version] }.uniq
        warn_schema_versions(versions)
        Result.new(
          sessions: records.select { |record| record[:type] == "session" },
          observations: records.select { |record| record[:type] == "method_observation" },
          schema_versions: versions
        )
      end

      private

      def records_in(path)
        records = []
        each_record(path) { |record| records << record }
        records
      end

      def each_record(path)
        File.foreach(path).with_index(1) do |line, lineno|
          stripped = line.strip
          next if stripped.empty?

          yield JSON.parse(stripped, symbolize_names: true)
        rescue JSON::ParserError => e
          @warn_io.puts("[ethotrace] skipping #{path}:#{lineno}: #{e.message}")
        end
      rescue Errno::ENOENT
        @warn_io.puts("[ethotrace] no such file: #{path}")
      end

      def warn_schema_versions(versions)
        if versions.size > 1
          @warn_io.puts("[ethotrace] mixed schema_version in input: #{versions.sort.join(", ")}")
        elsif versions.any? { |v| v != SCHEMA_VERSION }
          @warn_io.puts("[ethotrace] unknown schema_version #{versions.first} " \
                        "(this build supports #{SCHEMA_VERSION})")
        end
      end
    end
  end
end
