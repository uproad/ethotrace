# frozen_string_literal: true

# マージ済みの自己観測 JSONL を、Git に追跡させて公開できる成果物へ正規化する。
#
#   bundle exec ruby script/dogfood/normalize.rb [STORE]
#
# 生の観測ストアには環境依存・非決定的な要素が混じるため、そのままコミットすると
# 機微情報の漏洩(絶対パス)と無意味な差分(PID 由来の session_id・レコード順)を招く。
# 本スクリプトは次を施して同じファイルへ書き戻す:
#
#   - 全レコードの絶対パスを可搬な形へ畳む。リポジトリ内はルート相対(`gems/...`)、
#     gem インストール先は gem 相対(`gem:json-schema-6.2.0/...`)、それ以外のホーム
#     配下は `~/...` にして `/home/<user>/...` を漏らさない(site.path・io.read の
#     detail.path 等、ネストした値も再帰的に処理する)。
#   - レコードを owner / name / kind で決定的にソートし、再観測時の差分を安定させる。
#   - sessions 配列をソートする(観測 gem 単位の決定的 session_id が前提。observe.rb 参照)。
#
# session_id 自体の決定化は観測時に行う(`ETHOTRACE_DOGFOOD_SESSION`)。

require "json"
require "tmpdir"

STORE = ARGV.fetch(0, ENV.fetch("ETHOTRACE_SELF_STORE", "docs/self-observation.jsonl"))
ROOT = File.expand_path(ENV.fetch("ETHOTRACE_ROOT", Dir.pwd))
HOME = File.expand_path(Dir.home)
TMP = File.expand_path(Dir.tmpdir)

# テンポラリディレクトリ配下のパスは Dir.mktmpdir のランダムな第一成分を落として
# 決定的な末尾(`tmp:merged.jsonl` 等)に畳む。
def collapse_tmp(expanded)
  tail = expanded.delete_prefix("#{TMP}/").split("/", 2)[1]
  "tmp:#{tail || File.basename(expanded)}"
end

# 絶対パスらしい文字列だけを可搬な表現へ畳む。非パス文字列は素通り。
def portable(str)
  return str unless str.start_with?("/")

  expanded = File.expand_path(str)
  return expanded.delete_prefix("#{ROOT}/") if expanded.start_with?("#{ROOT}/")
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

puts "normalized #{STORE} (#{records.size} records; paths relativized to #{ROOT})"
