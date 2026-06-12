# frozen_string_literal: true

require "ethotrace"

RSpec.describe Ethotrace::Merge do
  def observation(owner:, name:, kind: "instance", return_classes: [], errors: [],
                  requirements: [], params: [], samples: 1, site: nil, **session)
    {
      schema_version: 1, type: "method_observation",
      method: { owner: owner, name: name, kind: kind },
      site: site, params: params, return: { classes_seen: return_classes },
      errors: errors, requirements: requirements, samples: samples, **session
    }
  end

  it "merges records of the same method by union and sums samples" do
    records = [
      observation(owner: "Order", name: "total", return_classes: ["Integer"], samples: 2, session: "a"),
      observation(owner: "Order", name: "total", return_classes: ["NilClass"], samples: 3, session: "b")
    ]
    merged = described_class.call(records)

    expect(merged.size).to eq(1)
    expect(merged.first).to include(
      method: { owner: "Order", name: "total", kind: "instance" },
      return: { classes_seen: %w[Integer NilClass] },
      samples: 5,
      sessions: %w[a b]
    )
  end

  it "emits valid method_observation records that are themselves re-mergeable" do
    once = observation(owner: "O", name: "m", return_classes: ["Integer"], samples: 1, session: "a")
    first_pass = described_class.call([once, once])
    # 既マージ結果(sessions 配列・samples 加算済み)を再度マージしても破綻しない。
    second_pass = described_class.call(first_pass + [observation(owner: "O", name: "m", samples: 4, session: "c")])

    expect(first_pass.first).to include(schema_version: 1, type: "method_observation")
    expect(second_pass.size).to eq(1)
    expect(second_pass.first[:samples]).to eq(6)
    expect(second_pass.first[:sessions]).to eq(%w[a c])
  end

  it "preserves full fidelity of errors (origin/from) unlike the display aggregator" do
    error = { class: "KeyError", origin: "inherited", from: "Hash#fetch" }
    merged = described_class.call([
                                    observation(owner: "O", name: "m", errors: [error]),
                                    observation(owner: "O", name: "m", errors: [error])
                                  ])
    expect(merged.first[:errors]).to eq([error])
  end

  it "preserves requirements detail and unions across records" do
    env = { kind: "env.read", write: false, direct: true, from: nil, detail: { key: "TAX_RATE" } }
    db = { kind: "db.query", write: false, direct: false, from: "Item#price", detail: { tables: ["items"] } }
    merged = described_class.call([
                                    observation(owner: "O", name: "m", requirements: [env]),
                                    observation(owner: "O", name: "m", requirements: [env, db])
                                  ])
    expect(merged.first[:requirements]).to eq([env, db])
  end

  it "unions param protocol and classes_seen by position, keeping arity/block" do
    base = { position: 0, name: "items", classes_seen: ["Array"],
             protocol: [{ name: "each", arity: 0, block: true }] }
    other = { position: 0, name: nil, classes_seen: ["Set"],
              protocol: [{ name: "size", arity: 0, block: false }] }
    merged = described_class.call([
                                    observation(owner: "O", name: "m", params: [base]),
                                    observation(owner: "O", name: "m", params: [other])
                                  ]).first
    param = merged[:params].first
    expect(param[:name]).to eq("items")
    expect(param[:classes_seen]).to eq(%w[Array Set])
    expect(param[:protocol]).to eq([
                                     { name: "each", arity: 0, block: true },
                                     { name: "size", arity: 0, block: false }
                                   ])
  end

  it "keeps distinct methods grouped and sorted by owner/name/kind" do
    merged = described_class.call([
                                    observation(owner: "Order", name: "total"),
                                    observation(owner: "Account", name: "balance"),
                                    observation(owner: "Order", name: "create", kind: "singleton")
                                  ])
    expect(merged.map { |r| r[:method].values_at(:owner, :name, :kind) }).to eq([
                                                                                  %w[Account balance instance],
                                                                                  %w[Order create singleton],
                                                                                  %w[Order total instance]
                                                                                ])
  end

  it "retains the first non-nil site" do
    merged = described_class.call([
                                    observation(owner: "O", name: "m", site: nil),
                                    observation(owner: "O", name: "m", site: { path: "o.rb", line: 3 })
                                  ])
    expect(merged.first[:site]).to eq(path: "o.rb", line: 3)
  end

  it "returns an empty array for no input" do
    expect(described_class.call([])).to eq([])
  end
end
