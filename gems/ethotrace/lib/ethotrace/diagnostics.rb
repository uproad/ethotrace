# frozen_string_literal: true

module Ethotrace
  # Ethotrace 自身の内部エラーの fail-safe 報告。
  #
  # 観測の記録・配信中に Ethotrace 内部で例外が起きても、観測対象(ユーザーコード)へ
  # 伝播させてはならない(挙動を変えない原則)。代わりに観測を黙って無効化し、ノイズに
  # ならないよう **プロセスで一度だけ** 警告する。probe(Wrapper)と sink(Collector)の
  # 双方がこの一回限りフラグを共有するため、独立モジュールに切り出す。
  module Diagnostics
    @reported = false

    module_function

    # 内部エラーを一度だけ警告する。2 回目以降は静かに無視する。
    def report_internal_error(error)
      return if @reported

      @reported = true
      warn "[ethotrace] internal error suppressed; observation disabled for this call: " \
           "#{error.class}: #{error.message}"
    end

    # 一回限りフラグを戻す(主にテスト用)。
    def reset!
      @reported = false
    end
  end
end
