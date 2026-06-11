# frozen_string_literal: true

source "https://rubygems.org"

# モノレポ内の各 gem を path 参照する。
# アダプタ gem(ethotrace-rspec 等)を追加したら gemspec 行をここに足す。
gemspec path: "gems/ethotrace", name: "ethotrace"

group :development, :test do
  gem "benchmark-ips", require: false
  gem "irb"
  gem "rake", "~> 13.0"
  gem "rspec", "~> 3.0"
  gem "rubocop", "~> 1.21", require: false
end
