# frozen_string_literal: true

require_relative "ethotrace/version"
require_relative "ethotrace/reentry_guard"
require_relative "ethotrace/call_context"
require_relative "ethotrace/argument_table"
require_relative "ethotrace/tracker"
require_relative "ethotrace/protocol_tracer"
require_relative "ethotrace/instrumentation"
require_relative "ethotrace/wrapper"
require_relative "ethotrace/jsonl_writer"
require_relative "ethotrace/instrumenter"
require_relative "ethotrace/adapter"
require_relative "ethotrace/adapter_registry"
require_relative "ethotrace/adapters/stdlib"
require_relative "ethotrace/isolation"
require_relative "ethotrace/session"
require_relative "ethotrace/merge"

# Ethotrace — Ruby 向け動的型検査・シグネチャ解析システムの core。
#
# 公称型(型名)ではなく、テスト実行中のメソッド呼び出しを観測して
# 「振る舞い(プロトコル)」「伝播例外」「実行環境要件(Requirements)」を
# 三チャネルで記録する。設計の詳細は ethotrace-design-handoff.md を、
# gem 間の安定契約である JSONL スキーマは docs/schema.md を参照。
module Ethotrace
  # gem 間の安定契約である JSONL 観測データのスキーマバージョン。
  # スキーマを変更する際はこの値を上げ、docs/schema.md を同時に更新すること。
  SCHEMA_VERSION = 1

  # Ethotrace 自身に起因するエラーの基底クラス。
  # 観測対象から伝播する例外(Error チャネル)とは区別する。
  class Error < StandardError; end
end
