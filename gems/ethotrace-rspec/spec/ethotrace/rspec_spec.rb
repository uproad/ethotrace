# frozen_string_literal: true

require "ethotrace/rspec"
require "tmpdir"
require_relative "../support/instrumentation_isolation"

RSpec.describe Ethotrace::RSpec do
  it "has a version number" do
    expect(Ethotrace::RSpec::VERSION).not_to be_nil
  end

  it "defines an Error rooted in the core Ethotrace::Error" do
    expect(Ethotrace::RSpec::Error.ancestors).to include(Ethotrace::Error)
  end

  describe ".setup" do
    include_context "isolated instrumentation"

    # before/after フックの登録だけを記録する fake な RSpec config。
    let(:fake_rspec) do
      Class.new do
        attr_reader :hooks

        def initialize
          @hooks = {}
        end

        def before(scope, &block)
          @hooks[[:before, scope]] = block
        end

        def after(scope, &block)
          @hooks[[:after, scope]] = block
        end
      end.new
    end

    it "registers before(:suite) and after(:suite) hooks and yields a configuration" do
      yielded = nil
      result = described_class.setup(rspec: fake_rspec) { |config| yielded = config }

      expect(result).to be_a(Ethotrace::RSpec::Configuration)
      expect(yielded).to be(result)
      expect(fake_rspec.hooks.keys).to contain_exactly(%i[before suite], %i[after suite])
    end

    it "starts the session on before(:suite) and clears it on after(:suite)" do
      Dir.mktmpdir do |dir|
        described_class.setup(rspec: fake_rspec) do |config|
          config.output_dir = dir
          config.session_id = "hooked"
        end

        fake_rspec.hooks[%i[before suite]].call
        begin
          expect(described_class.session).to be_a(Ethotrace::Session)
        ensure
          fake_rspec.hooks[%i[after suite]].call
        end
        expect(described_class.session).to be_nil
        expect(File).to exist(File.join(dir, "hooked.jsonl"))
      end
    end
  end
end
