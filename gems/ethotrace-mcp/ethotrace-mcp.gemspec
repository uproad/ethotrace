# frozen_string_literal: true

require_relative "lib/ethotrace/mcp/version"

Gem::Specification.new do |spec|
  spec.name = "ethotrace-mcp"
  spec.version = Ethotrace::MCP::VERSION
  spec.authors = ["uproad"]
  spec.email = ["7349115+uproad@users.noreply.github.com"]

  spec.summary = "Ethotrace の観測結果を提供する MCP サーバ"
  spec.description = "Ethotrace の観測データ(observations.jsonl)を読み、メソッドの規約・" \
                     "伝播例外・Requirements を MCP ツールとして公開するサーバ gem。" \
                     "観測プロセスとは完全分離したデータ消費者であり、計装は一切ロードしない。"
  spec.homepage = "https://github.com/uproad/ethotrace"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/uproad/ethotrace"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore .rspec spec/ .rubocop.yml])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # core への依存(観測の物理学)。MCP は core の消費側コード(Reader / Merge /
  # schema 定数)経由で観測データを読むだけで、計装は一切起動しない。
  spec.add_dependency "ethotrace", Ethotrace::MCP::VERSION
end
