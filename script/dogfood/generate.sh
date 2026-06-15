#!/usr/bin/env bash
# 各 gem の root で、その gem の安全な spec を Ethotrace 自身で観測し、観測成果物
# (docs/self-observation.{jsonl,md})を各 gem 配下に生成する。
#
#   script/dogfood/generate.sh
#
# 生ログは OS 一時ディレクトリに出して各 gem を汚さない。site.path は実行時の作業
# ディレクトリ(= その gem の root)相対で記録される。詳細は script/dogfood/observe.rb。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OBSERVE="$ROOT/script/dogfood/observe.rb"

# gem キー → "<gem ディレクトリ> <安全な spec...>"
run_gem() {
  local gem_key="$1" gem_dir="$2"
  shift 2
  local raw
  raw="$(mktemp -d)"
  echo ">>> [$gem_key] $gem_dir"
  (
    cd "$ROOT/$gem_dir"
    mkdir -p docs
    ETHOTRACE_DOGFOOD_SESSION="$gem_key" ETHOTRACE_DOGFOOD_OUT="$raw" \
      bundle exec rspec -r "$OBSERVE" -I spec "$@" >/dev/null
    bundle exec ethotrace merge "$raw"/*.jsonl -o docs/self-observation.jsonl
    bundle exec ruby "$ROOT/script/dogfood/normalize.rb" docs/self-observation.jsonl
    ETHOTRACE_SELF_GEM="$gem_key" ETHOTRACE_DOGFOOD_OUT="$raw" \
      bundle exec ruby "$ROOT/script/dogfood/report.rb"
  )
  rm -rf "$raw"
}

run_gem core  gems/ethotrace       spec/ethotrace/merge_spec.rb spec/ethotrace/cli
run_gem mcp   gems/ethotrace-mcp   spec/ethotrace/mcp_spec.rb spec/ethotrace/mcp
run_gem rspec gems/ethotrace-rspec spec/ethotrace/rspec/configuration_spec.rb

echo ">>> done"
