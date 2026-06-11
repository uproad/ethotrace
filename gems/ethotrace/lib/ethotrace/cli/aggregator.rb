# frozen_string_literal: true

module Ethotrace
  module CLI
    # 表示用にマージ済みの 1 メソッドの観測。docs/schema.md §4 のサブセットを
    # 値オブジェクトとして保持し、サマリ用の派生値を提供する。
    MethodObservation = Data.define(
      :owner, :name, :kind, :site,
      :params, :return_classes, :errors, :requirements, :samples, :sessions
    ) do
      # `Owner#name`(インスタンス)/ `Owner.name`(特異)形式の識別子。
      def id
        separator = kind == "singleton" ? "." : "#"
        "#{owner}#{separator}#{name}"
      end

      # 引数に対して呼び出されたメソッド(プロトコル)の総種類数。
      def protocol_count
        params.sum { |param| param[:protocol].size }
      end

      # 観測されたエラーの種類数。
      def error_type_count
        errors.size
      end

      # サマリ用の戻り値クラス表記(未観測なら nil)。
      def return_summary
        return_classes.empty? ? nil : return_classes.join(", ")
      end
    end

    # 複数セッションの method_observation を docs/schema.md §7 のマージ意味論で
    # 表示用に統合する。`(owner, name, kind)` をキーに、配列系は和集合、samples は
    # 加算。`observations.json` を書き出す本来のマージ CLI とは別で、メモリ上の
    # 表示専用統合である。
    class Aggregator
      # 和集合で統合する配列系フィールドと、レコードからの取り出し方の対応。
      UNION_FIELDS = {
        return_classes: ->(observation) { Array(observation.dig(:return, :classes_seen)) },
        errors: ->(observation) { Array(observation[:errors]) },
        requirements: ->(observation) { Array(observation[:requirements]) },
        sessions: ->(observation) { Array(observation[:session]) }
      }.freeze
      private_constant :UNION_FIELDS

      # @param observations [Array<Hash>] 生の method_observation レコード(symbol キー)。
      # @return [Array<MethodObservation>] owner/name/kind 順にソート済み。
      def self.call(observations)
        groups = {}
        observations.each { |observation| accumulate(groups, observation) }
        groups.values
              .map { |group| build(group) }
              .sort_by { |observation| [observation.owner, observation.name, observation.kind] }
      end

      def self.accumulate(groups, observation)
        merge_into(group_for(groups, observation[:method]), observation)
      end

      def self.group_for(groups, method)
        groups[[method[:owner], method[:name], method[:kind]]] ||= blank_group(method)
      end

      def self.merge_into(group, observation)
        group[:site] ||= observation[:site]
        group[:samples] += observation.fetch(:samples, 1)
        UNION_FIELDS.each { |field, extract| group[field] |= extract.call(observation) }
        merge_params(group[:params], Array(observation[:params]))
      end

      def self.blank_group(method)
        {
          owner: method[:owner], name: method[:name], kind: method[:kind],
          site: nil, params: {}, return_classes: [], errors: [],
          requirements: [], samples: 0, sessions: []
        }
      end

      # 引数プロトコルを position ごとに和集合で統合する(M1 では空)。
      def self.merge_params(accumulated, incoming)
        incoming.each do |param|
          slot = (accumulated[param[:position]] ||= {
            position: param[:position], name: param[:name], protocol: [], classes_seen: []
          })
          slot[:name] ||= param[:name]
          slot[:protocol] |= Array(param[:protocol])
          slot[:classes_seen] |= Array(param[:classes_seen])
        end
      end

      def self.build(group)
        params = group[:params].keys.sort.map { |position| group[:params][position] }
        MethodObservation.new(
          owner: group[:owner], name: group[:name], kind: group[:kind], site: group[:site],
          params: params, return_classes: group[:return_classes], errors: group[:errors],
          requirements: group[:requirements], samples: group[:samples], sessions: group[:sessions]
        )
      end

      private_class_method :accumulate, :group_for, :merge_into, :blank_group, :merge_params, :build
    end
  end
end
