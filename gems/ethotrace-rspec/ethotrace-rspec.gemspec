# frozen_string_literal: true

require_relative "lib/ethotrace/rspec/version"

Gem::Specification.new do |spec|
  spec.name = "ethotrace-rspec"
  spec.version = Ethotrace::RSpec::VERSION
  spec.authors = ["uproad"]
  spec.email = ["7349115+uproad@users.noreply.github.com"]

  spec.summary = "Ethotrace の RSpec ライフサイクル接続アダプタ"
  spec.description = "RSpec のスイート開始/終了に Ethotrace の観測セッションを接続し、" \
                     "ワーカーごとに tmp/ethotrace/<session>.jsonl を書き出すアダプタ gem。" \
                     "観測の物理学は core(ethotrace)に委ね、本 gem は意味論に徹する。"
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

  # core への依存(観測の物理学)。アダプタは core の公開 API 経由で接続する。
  spec.add_dependency "ethotrace", Ethotrace::RSpec::VERSION
end
