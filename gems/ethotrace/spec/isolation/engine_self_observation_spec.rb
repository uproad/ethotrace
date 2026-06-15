# frozen_string_literal: true

require "open3"
require "json"
require "tmpdir"

# エンジン本体の自己観測ハーネス(script/self_observe_engine.rb)の E2E 回帰。
#
# BoxIsolation で box 内 Ethotrace のエンジン内部(deny-list 外)を観測し、観測契約の
# JSONL を生成すること、および記録の活性パス(deny-list)が Box でも wrap を拒否される
# ことを固定する。ハーネスは main box を要するため、RUBY_BOX=1 の素の ruby サブプロセス
# として起動する(bundle/spec_helper の RUBY_BOX 問題を踏まない)。出力はコミット済み
# 成果物を汚さないよう一時ディレクトリへ向ける。
RSpec.describe "engine self-observation E2E (design §4.8 / §9 M5)" do
  script = File.expand_path("../../script/self_observe_engine.rb", __dir__)

  before do
    skip "Ruby >= 4.0 が必要(Ruby::Box は 4.0 で導入)" unless RUBY_VERSION.to_f >= 4.0
  end

  it "observes box-side engine internals and emits a contract, while the deny-list refuses the recording path" do
    Dir.mktmpdir do |dir|
      jsonl = File.join(dir, "engine.jsonl")
      env = {
        "RUBY_BOX" => "1",
        "ETHOTRACE_ENGINE_JSONL" => jsonl,
        "ETHOTRACE_ENGINE_MD" => File.join(dir, "engine.md")
      }
      out, err, status = Open3.capture3(env, RbConfig.ruby, script)

      records = File.exist?(jsonl) ? File.readlines(jsonl).map { |line| JSON.parse(line) } : []
      observed = records.map { |r| "#{r.dig("method", "owner")}##{r.dig("method", "name")}" }

      aggregate_failures do
        expect(status).to be_success, "harness exited non-zero:\n#{err}"
        # 記録の活性パス(deny-list)は Box でも wrap を拒否される(defense-in-depth)。
        expect(out).to match(/deny-list refused .*Tracker.*Wrapper.*Collector/)
        # エンジン内部の公開 API が観測され、Ethotrace 自身のレコードだけが出ること。
        expect(records).not_to be_empty
        expect(observed).to all(start_with("Ethotrace::"))
        # 出力シンク自身の Requirements(io.write)を観測できること = Box の固有価値。
        writer_open = records.find { |r| r.dig("method", "owner") == "Ethotrace::JSONLWriter" && r.dig("method", "name") == "open" }
        expect(writer_open).not_to be_nil
        expect(writer_open["requirements"].map { |x| x["kind"] }).to include("io.write")
      end
    end
  end
end
