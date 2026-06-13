# frozen_string_literal: true

require "ethotrace"
require "ethotrace/cli/reader"

module Ethotrace
  module MCP
    # 観測データ(`observations.jsonl`)を読み、メソッド単位の規約をクエリする層。
    #
    # MCP プロトコルからは独立した純 Ruby のクエリ層であり、これ単体でテストできる。
    # 入力は schema_version 付き JSONL(`docs/schema.md`)。読み込みには core の消費側
    # コード(`CLI::Reader`)を、統合には `Ethotrace::Merge` を再利用する。生ログ・
    # マージ済みストアのどちらを渡しても、常に `(owner, name, kind)` で和集合へ正規化した
    # method_observation レコード(symbol キー)を返す。
    #
    # 返すのは JSONL スキーマそのままの Hash であり、MCP ツール層はこれを JSON へ直に
    # シリアライズする。「観測された下限(observed contract)」である点(未実行パスは
    # 含まれない)は core の仕様をそのまま引き継ぐ。
    class Catalog
      # メソッドの非決定性(flaky 容疑)を示す Requirements の語彙。
      # これらに接触するメソッドはテストの再現性を損ないうる(設計資料 §9)。
      NONDETERMINISM_KINDS = %w[time.read random.read].freeze

      # 1 つ以上の JSONL からカタログを構築する。
      #
      # @param paths [Array<String>] 観測 JSONL のパス(生ログでもマージ済みでも可)。
      # @param warn_io [IO] 壊れた行・schema_version 不整合の警告先。
      # @return [Catalog]
      def self.load(*paths, warn_io: $stderr)
        result = CLI::Reader.new(warn_io: warn_io).read(paths.flatten)
        new(Merge.call(result.observations))
      end

      # @param records [Array<Hash>] マージ済み method_observation レコード(symbol キー)。
      def initialize(records)
        @records = records.freeze
        @index = records.to_h { |record| [key_of(record[:method]), record] }.freeze
      end

      # 全メソッドのレコード(owner/name/kind 順にソート済み)。
      # @return [Array<Hash>]
      def methods
        @records
      end

      # 1 メソッドの規約を引く。
      #
      # @param owner [String] 完全修飾の定義クラス/モジュール名。
      # @param name [String] メソッド名。
      # @param kind [String] "instance" / "singleton"。
      # @return [Hash, nil] 該当レコード。未観測なら nil。
      def lookup(owner:, name:, kind: "instance")
        @index[[owner, name, kind]]
      end

      private

      def key_of(method)
        [method[:owner], method[:name], method[:kind]]
      end
    end
  end
end
