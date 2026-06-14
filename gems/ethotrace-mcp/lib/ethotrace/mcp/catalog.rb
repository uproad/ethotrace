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

      # Requirements が空のメソッド(R=∅ = 純粋の容疑)。外部世界に一切接触せず
      # 観測されたメソッド一覧。observed contract の下限である点に注意(未実行パスの
      # 接触は含まれない)。
      # @return [Array<Hash>]
      def pure_methods
        @records.select { |record| Array(record[:requirements]).empty? }
      end

      # 非決定性 Requirements(既定: time.read / random.read)に接触するメソッド。
      # テストの再現性を損ないうる flaky 容疑(設計資料 §9)。
      # @param kinds [Array<String>] flaky とみなす Requirements の語彙。
      # @return [Array<Hash>]
      def flaky_suspects(kinds: NONDETERMINISM_KINDS)
        wanted = kinds.to_set
        @records.select { |record| requirement_kinds(record).intersect?(wanted) }
      end

      # 例外をエスケープさせうるメソッド(Error チャネルが非空)。
      # @param exception [String, nil] 指定時はその例外クラスを投げるものだけに絞る。
      # @return [Array<Hash>]
      def raisers(exception: nil)
        with_errors = @records.reject { |record| Array(record[:errors]).empty? }
        return with_errors unless exception

        with_errors.select { |record| error_classes(record).include?(exception) }
      end

      # 特定のエフェクト語彙(例: db.query / env.read)に接触するメソッド。
      # @param kind [String] Requirements の語彙(`docs/schema.md` §5)。
      # @return [Array<Hash>]
      def requiring(kind:)
        @records.select { |record| requirement_kinds(record).include?(kind) }
      end

      # 1 メソッドがエスケープさせうる例外クラス名の一覧。
      # @return [Array<String>, nil] 未観測メソッドなら nil。
      def exceptions_of(owner:, name:, kind: "instance")
        record = lookup(owner: owner, name: name, kind: kind)
        record && error_classes(record).to_a
      end

      # 1 メソッドの特定引数(position 起点 0)に対して観測されたプロトコル。
      # @return [Array<Hash>, nil] 未観測のメソッド/引数なら nil。
      def param_protocol(owner:, name:, position:, kind: "instance")
        record = lookup(owner: owner, name: name, kind: kind)
        param = record && Array(record[:params]).find { |slot| slot[:position] == position }
        param && param[:protocol]
      end

      private

      def key_of(method)
        [method[:owner], method[:name], method[:kind]]
      end

      def requirement_kinds(record)
        Array(record[:requirements]).to_set { |requirement| requirement[:kind] }
      end

      def error_classes(record)
        Array(record[:errors]).to_set { |error| error[:class] }
      end
    end
  end
end
