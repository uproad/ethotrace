# frozen_string_literal: true

require "ethotrace/rspec"
require "ethotrace/cli"
require "tmpdir"
require "json"
require_relative "../support/instrumentation_isolation"

# ethotrace-rspec が吐いたワーカー別 JSONL を `ethotrace merge` で統合する
# パイプライン全体のゴールデン検証。観測 → 直列化 → マージが結合することを示す。
RSpec.describe "ethotrace-rspec to merge CLI end-to-end" do
  include_context "isolated instrumentation"

  around do |example|
    Dir.mktmpdir { |dir| @dir = dir and example.run }
  end

  # 観測対象は例ごとに新しいクラスを使う。reset! はレジストリを空にするが
  # prepend 済みモジュールは外せないため、同じクラスを複数例で再 wrap すると
  # ラッパーが二重化する。stub_const で例ごとに新鮮な名前付きクラスを与える。
  before do
    stub_const("EndToEndOrder", Class.new do
      def total(items)
        items.sum
      end
    end)
  end

  # 1 ワーカー分の観測セッションを回す。ブロック内の呼び出しが観測対象。
  def observe_session(id)
    config = Ethotrace::RSpec::Configuration.new
    config.output_dir = @dir
    config.session_id = id
    config.observe(EndToEndOrder, methods: %i[total])
    session = Ethotrace::RSpec::SessionRunner.start(config)
    yield
  ensure
    Ethotrace::RSpec::SessionRunner.finish(session)
  end

  def merge_to(output, *inputs)
    status = Ethotrace::CLI::MergeCommand
             .new(out: StringIO.new, err: StringIO.new)
             .run([*inputs, "-o", output])
    raise "merge failed: #{status}" unless status.zero?

    File.readlines(output).map { |line| JSON.parse(line, symbolize_names: true) }
  end

  it "merges per-worker observations into a single re-mergeable record" do
    observe_session("w1") { EndToEndOrder.new.total([1, 2, 3]) }
    observe_session("w2") { EndToEndOrder.new.total([10, 20]) }

    output = File.join(@dir, "observations.jsonl")
    merged = merge_to(output, File.join(@dir, "w1.jsonl"), File.join(@dir, "w2.jsonl"))

    expect(merged.size).to eq(1)
    record = merged.first
    # site は絶対パス(source_location)のため、決定的なゴールデン比較から外す。
    expect(record.delete(:site)).to include(:path, :line)

    expect(record).to eq(
      schema_version: 1,
      type: "method_observation",
      method: { owner: "EndToEndOrder", name: "total", kind: "instance" },
      params: [
        { position: 0, name: "items", protocol: [], classes_seen: ["Array"] }
      ],
      return: { classes_seen: ["Integer"] },
      errors: [],
      requirements: [],
      samples: 2,
      sessions: %w[w1 w2]
    )
  end

  it "produces output that re-merges with a fresh worker log" do
    observe_session("w1") { EndToEndOrder.new.total([1]) }
    first = File.join(@dir, "observations.jsonl")
    merge_to(first, File.join(@dir, "w1.jsonl"))

    observe_session("w2") { EndToEndOrder.new.total([2]) }
    final = File.join(@dir, "final.jsonl")
    # 既マージの observations.jsonl と新しい生ログを再マージする。
    remerged = merge_to(final, first, File.join(@dir, "w2.jsonl"))

    expect(remerged.size).to eq(1)
    expect(remerged.first[:samples]).to eq(2)
    expect(remerged.first[:sessions]).to eq(%w[w1 w2])
  end
end
