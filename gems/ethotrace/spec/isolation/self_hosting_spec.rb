# frozen_string_literal: true

require "open3"

# 自己適用(self-hosting)E2E(設計資料 v2 §4.8 / §9 M5)。
#
# BoxIsolation は **main box からの起動**を前提とする(非 main box の子 box は親定義を
# 共有し分離しない。さらに共有系譜では RootSink が再帰する)。RSpec ランナー自体は
# RUBY_BOX=1 でも非 main の root box で動くため、ここでは E2E ハーネス
# (script/self_hosting.rb)を **RUBY_BOX=1 の素の ruby サブプロセス = main box** として
# 起動し、その出力で「Ethotrace が自身を観測してレコードを得る」ことを実証する。
#
# Ruby >= 4.0 でのみ Ruby::Box が存在するため、それ未満では skip する。bundler を介さず
# 素の ruby を起動するので、RUBY_BOX 下の bundle/spec_helper 問題も踏まない。
RSpec.describe "self-hosting E2E (design §4.8 / §9 M5)" do
  script = File.expand_path("../../script/self_hosting.rb", __dir__)

  before do
    skip "Ruby >= 4.0 が必要(Ruby::Box は 4.0 で導入)" unless RUBY_VERSION.to_f >= 4.0
  end

  it "observes box-side Ethotrace from a main box and emits its own observation record" do
    out, err, status = Open3.capture3({ "RUBY_BOX" => "1" }, RbConfig.ruby, script)

    aggregate_failures do
      expect(status).to be_success, "harness exited non-zero:\n#{err}"
      # 観測者(root)と観測対象(box 内 Ethotrace コピー)が別実体であること。
      expect(out).to include("main box=true")
      expect(out).to match(/box Ethotrace separated from root\? true/)
      # 記録の活性パスは box 内でも deny-list で計装対象から除外されること。
      expect(out).to match(/deny-list still protects box-side recording path\? true/)
      # Ethotrace 自身のメソッドの観測レコード(observed contract)が得られること。
      expect(out).to match(/Ethotrace::Merge#call -> \["Array"\]/)
    end
  end
end
