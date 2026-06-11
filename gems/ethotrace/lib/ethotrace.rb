# frozen_string_literal: true

require_relative "ethotrace/version"

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
