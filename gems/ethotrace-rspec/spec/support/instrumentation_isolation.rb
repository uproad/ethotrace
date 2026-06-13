# frozen_string_literal: true

require "ethotrace"

# core の計装はプロセスグローバル(Wrapper / AdapterRegistry / Tracker)。
# 1 プロセスで複数セッションを回すテストでは、例ごとに状態を初期化しないと
# セッション間の登録が残る(AdapterRegistry はクラス重複登録を無視するため、
# 前の例の TargetAdapter が残ると新しい観測対象が wrap されない)。本物の
# セッションを起動する例はこのコンテキストを include して状態を分離する。
RSpec.shared_context "isolated instrumentation" do
  before { reset_ethotrace_instrumentation! }
  after { reset_ethotrace_instrumentation! }

  def reset_ethotrace_instrumentation!
    Ethotrace::Adapters::Stdlib.disable
    Ethotrace::Wrapper.reset!
    Ethotrace::Collector.reset!
    Ethotrace::Diagnostics.reset!
    Ethotrace::AdapterRegistry.reset!
    Ethotrace::Tracker.reset
  end
end
