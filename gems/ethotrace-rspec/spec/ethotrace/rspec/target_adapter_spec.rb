# frozen_string_literal: true

require "ethotrace/rspec"

RSpec.describe Ethotrace::RSpec::TargetAdapter do
  # wrap_method の呼び出しだけを記録する fake instrumenter。
  let(:instrumenter) do
    Struct.new(:calls) do
      def wrap_method(klass, name, kind:)
        calls << [klass, name, kind]
      end
    end.new([])
  end

  describe Ethotrace::RSpec::Target do
    it "lists the explicitly named methods with the target kind" do
      target = described_class.new(klass: String, method_names: %i[upcase downcase], kind: :instance)
      expect(target.method_specs).to eq([%i[upcase instance], %i[downcase instance]])
    end

    it "lists a class's own instance methods (excluding inherited) when method_names is nil" do
      klass = Class.new do
        def own_one; end
        def own_two; end
      end
      target = described_class.new(klass: klass, method_names: nil, kind: :instance)
      expect(target.method_specs).to contain_exactly(%i[own_one instance], %i[own_two instance])
    end

    it "lists a class's own singleton methods for kind: :singleton" do
      klass = Class.new do
        def self.build; end
      end
      target = described_class.new(klass: klass, method_names: nil, kind: :singleton)
      expect(target.method_specs).to eq([%i[build singleton]])
    end
  end

  describe "#install" do
    it "wraps every method of every target through the instrumenter" do
      targets = [
        Ethotrace::RSpec::Target.new(klass: String, method_names: %i[upcase], kind: :instance),
        Ethotrace::RSpec::Target.new(klass: Integer, method_names: %i[abs], kind: :singleton)
      ]
      described_class.new(targets).install(instrumenter)

      expect(instrumenter.calls).to eq([
                                         [String, :upcase, :instance],
                                         [Integer, :abs, :singleton]
                                       ])
    end

    it "reports its name as rspec-targets" do
      expect(described_class.new([]).name).to eq("rspec-targets")
    end
  end
end
