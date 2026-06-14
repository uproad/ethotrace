# frozen_string_literal: true

# マージ済みの自己観測 JSONL を、Git に追跡させて公開できる成果物へ仕上げる。
#
#   bundle exec ruby script/dogfood/normalize.rb [STORE]
#
# **観測対象プロジェクト配下のパス(`site.path` や base 配下の io パス)は core が
# 観測時点で相対化済み**(`Ethotrace::PathNormalizer`)。本スクリプトが扱うのは
# core が相対化できない残り、すなわち **base の外を指す絶対パス**(io エフェクトが
# 触れた third-party gem のリソースや tmp ファイル等)と、観測のたびに変わる
# 非決定要素だけ。次を施して同じファイルへ書き戻す:
#
#   - base 外の絶対パスを可搬な形へ畳む。gem インストール先は gem 相対
#     (`gem:json-schema-6.2.0/...`)、tmp 配下は `tmp:...`、その他のホーム配下は
#     `~/...` にして `/home/<user>/...` を漏らさない(detail.path 等、ネストした値も
#     再帰的に処理する)。
#   - レコードを owner / name / kind で決定的にソートし、再観測時の差分を安定させる。
#   - sessions 配列をソートする(観測 gem 単位の決定的 session_id が前提。observe.rb 参照)。
#
# session_id 自体の決定化は観測時に行う(`ETHOTRACE_DOGFOOD_SESSION`)。

require "json"
require "tmpdir"

STORE = ARGV.fetch(0, ENV.fetch("ETHOTRACE_SELF_STORE", "docs/self-observation.jsonl"))
HOME = File.expand_path(Dir.home)
TMP = File.expand_path(Dir.tmpdir)

# テンポラリディレクトリ配下のパスは Dir.mktmpdir のランダムな第一成分を落として
# 決定的な末尾(`tmp:merged.jsonl` 等)に畳む。
def collapse_tmp(expanded)
  tail = expanded.delete_prefix("#{TMP}/").split("/", 2)[1]
  "tmp:#{tail || File.basename(expanded)}"
end

# base の外を指す絶対パスだけを可搬な表現へ畳む。相対パス(core が正規化済み)や
# 非パス文字列は素通り。
def portable(str)
  return str unless str.start_with?("/")

  expanded = File.expand_path(str)
  return "gem:#{expanded.split("/gems/").last}" if expanded.include?("/gems/")
  return collapse_tmp(expanded) if expanded.start_with?("#{TMP}/")
  return "~/#{expanded.delete_prefix("#{HOME}/")}" if expanded.start_with?("#{HOME}/")

  str
end

def deep_portable(obj)
  case obj
  when Hash then obj.transform_values { |v| deep_portable(v) }
  when Array then obj.map { |v| deep_portable(v) }
  when String then portable(obj)
  else obj
  end
end

records = File.readlines(STORE).map { |line| deep_portable(JSON.parse(line)) }
records.each { |rec| rec["sessions"] = Array(rec["sessions"]).sort if rec.key?("sessions") }

def sort_key(rec)
  m = rec["method"] || {}
  [m["owner"].to_s, m["name"].to_s, m["kind"].to_s]
end

records.sort_by! { |rec| rec["type"] == "method_observation" ? [0, *sort_key(rec)] : [1, rec["type"].to_s, ""] }

File.open(STORE, "w") do |io|
  records.each { |rec| io.puts(JSON.generate(rec)) }
end

puts "normalized #{STORE} (#{records.size} records; base-external paths collapsed)"
