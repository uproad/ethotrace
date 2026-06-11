# frozen_string_literal: true

require "rspec/core/rake_task"
require "rubocop/rake_task"

# モノレポ内の全 gem の spec ディレクトリを load path に追加する。
# 各 gem の spec は .rspec の --require spec_helper で spec_helper を読む。
SPEC_LOAD_PATHS = Dir["gems/*/spec"].freeze

RSpec::Core::RakeTask.new(:spec) do |t|
  t.pattern = "gems/*/spec/**/*_spec.rb"
  t.rspec_opts = SPEC_LOAD_PATHS.map { |p| "-I #{p}" }.join(" ")
end

RuboCop::RakeTask.new

task default: %i[spec rubocop]
