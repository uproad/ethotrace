# frozen_string_literal: true

require "ethotrace/cli"

RSpec.describe Ethotrace::CLI::Aggregator do
  def observation(owner:, name:, kind: "instance", return_classes: [], errors: [],
                  requirements: [], params: [], samples: 1, session: "s1", site: nil)
    {
      schema_version: 1, type: "method_observation",
      method: { owner: owner, name: name, kind: kind },
      site: site, params: params, return: { classes_seen: return_classes },
      errors: errors, requirements: requirements, samples: samples, session: session
    }
  end

  it "merges records of the same method by union and sums samples" do
    records = [
      observation(owner: "Order", name: "total", return_classes: ["Integer"], samples: 2, session: "a"),
      observation(owner: "Order", name: "total", return_classes: ["NilClass"], samples: 3, session: "b",
                  errors: [{ class: "KeyError", origin: "direct", from: nil }])
    ]
    merged = described_class.call(records)

    expect(merged.size).to eq(1)
    expect(merged.first.return_classes).to eq(%w[Integer NilClass])
    expect(merged.first.samples).to eq(5)
    expect(merged.first.sessions).to eq(%w[a b])
    expect(merged.first.error_type_count).to eq(1)
  end

  it "deduplicates identical errors across records" do
    error = { class: "KeyError", origin: "direct", from: nil }
    merged = described_class.call([
                                    observation(owner: "O", name: "m", errors: [error]),
                                    observation(owner: "O", name: "m", errors: [error])
                                  ])
    expect(merged.first.errors).to eq([error])
  end

  it "keeps distinct methods grouped and sorted by owner/name/kind" do
    merged = described_class.call([
                                    observation(owner: "Order", name: "total"),
                                    observation(owner: "Account", name: "balance"),
                                    observation(owner: "Order", name: "create", kind: "singleton")
                                  ])
    expect(merged.map(&:id)).to eq(["Account#balance", "Order.create", "Order#total"])
  end

  it "retains the first non-nil site" do
    merged = described_class.call([
                                    observation(owner: "O", name: "m", site: nil),
                                    observation(owner: "O", name: "m", site: { path: "o.rb", line: 3 })
                                  ])
    expect(merged.first.site).to eq(path: "o.rb", line: 3)
  end

  describe "MethodObservation derived values" do
    it "formats id with # for instance and . for singleton" do
      instance = described_class.call([observation(owner: "O", name: "m")]).first
      singleton = described_class.call([observation(owner: "O", name: "m", kind: "singleton")]).first
      expect(instance.id).to eq("O#m")
      expect(singleton.id).to eq("O.m")
    end

    it "counts protocol entries across params" do
      params = [
        { position: 0, name: "items",
          protocol: [{ name: "each", arity: 0, block: true }, { name: "size", arity: 0, block: false }],
          classes_seen: ["Array"] }
      ]
      merged = described_class.call([observation(owner: "O", name: "m", params: params)]).first
      expect(merged.protocol_count).to eq(2)
    end

    it "unions param protocol and classes_seen by position across records" do
      base = { position: 0, name: "items", classes_seen: ["Array"],
               protocol: [{ name: "each", arity: 0, block: true }] }
      other = { position: 0, name: "items", classes_seen: ["Set"],
                protocol: [{ name: "size", arity: 0, block: false }] }
      merged = described_class.call([
                                      observation(owner: "O", name: "m", params: [base]),
                                      observation(owner: "O", name: "m", params: [other])
                                    ]).first
      expect(merged.params.first[:classes_seen]).to eq(%w[Array Set])
      expect(merged.params.first[:protocol].size).to eq(2)
    end

    it "summarizes return as nil when nothing was observed" do
      merged = described_class.call([observation(owner: "O", name: "m")]).first
      expect(merged.return_summary).to be_nil
    end
  end
end
