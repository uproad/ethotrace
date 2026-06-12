# frozen_string_literal: true

module Ethotrace
  # 複数セッションの method_observation を docs/schema.md §7 のマージ意味論で
  # 統合する、core の正規マージ。
  #
  # `(owner, name, kind)` をキーに、配列系フィールド(params のプロトコル・
  # classes_seen・errors・requirements)は和集合、`samples` は加算する。表示用に
  # フィールドを間引く {CLI::Aggregator} と異なり、こちらは errors の origin/from、
  # requirements の detail、プロトコルの arity/block まで**データを一切捨てない**。
  # マージ結果は `ethotrace merge` が observations.jsonl として書き出す。
  #
  # 出力レコードは入力と同じ method_observation 形を保つ(`schema_version` /
  # `type` を持つ)ため、**再びマージ可能**である。単一観測の `session`(文字列)
  # と既マージの `sessions`(配列)のどちらも入力として受け付け、常に `sessions`
  # 配列へ正規化して出力する。
  class Merge
    # 和集合で統合する配列系フィールドと、レコードからの取り出し方の対応。
    UNION_FIELDS = {
      return_classes: ->(observation) { Array(observation.dig(:return, :classes_seen)) },
      errors: ->(observation) { Array(observation[:errors]) },
      requirements: ->(observation) { Array(observation[:requirements]) }
    }.freeze
    private_constant :UNION_FIELDS

    # @param observations [Array<Hash>] 生の method_observation レコード(symbol キー)。
    # @return [Array<Hash>] owner/name/kind 順にソート済みのマージ済みレコード。
    def self.call(observations)
      groups = {}
      observations.each { |observation| accumulate(groups, observation) }
      groups.values
            .map { |group| build(group) }
            .sort_by { |record| record[:method].values_at(:owner, :name, :kind) }
    end

    def self.accumulate(groups, observation)
      method = observation[:method]
      key = [method[:owner], method[:name], method[:kind]]
      merge_into(groups[key] ||= blank_group(method), observation)
    end

    def self.blank_group(method)
      {
        method: { owner: method[:owner], name: method[:name], kind: method[:kind] },
        site: nil, params: {}, return_classes: [], errors: [],
        requirements: [], samples: 0, sessions: []
      }
    end

    def self.merge_into(group, observation)
      group[:site] ||= observation[:site]
      group[:samples] += observation.fetch(:samples, 1)
      group[:sessions] |= sessions_of(observation)
      UNION_FIELDS.each { |field, extract| group[field] |= extract.call(observation) }
      merge_params(group[:params], Array(observation[:params]))
    end

    # 単一観測の `session`(文字列)と既マージの `sessions`(配列)の双方を許す。
    def self.sessions_of(observation)
      Array(observation[:sessions]) | Array(observation[:session])
    end

    # 引数プロトコルを position ごとに和集合で統合する。
    def self.merge_params(accumulated, incoming)
      incoming.each do |param|
        slot = (accumulated[param[:position]] ||= {
          position: param[:position], name: nil, protocol: [], classes_seen: []
        })
        slot[:name] ||= param[:name]
        slot[:protocol] |= Array(param[:protocol])
        slot[:classes_seen] |= Array(param[:classes_seen])
      end
    end

    def self.build(group)
      {
        schema_version: SCHEMA_VERSION, type: "method_observation",
        method: group[:method], site: group[:site],
        params: group[:params].keys.sort.map { |position| group[:params][position] },
        return: { classes_seen: group[:return_classes] },
        errors: group[:errors], requirements: group[:requirements],
        samples: group[:samples], sessions: group[:sessions].sort
      }
    end

    private_class_method :accumulate, :blank_group, :merge_into,
                         :sessions_of, :merge_params, :build
  end
end
