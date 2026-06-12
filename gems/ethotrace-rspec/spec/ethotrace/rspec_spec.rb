# frozen_string_literal: true

require "ethotrace/rspec"

RSpec.describe Ethotrace::RSpec do
  it "has a version number" do
    expect(Ethotrace::RSpec::VERSION).not_to be_nil
  end

  it "defines an Error rooted in the core Ethotrace::Error" do
    expect(Ethotrace::RSpec::Error.ancestors).to include(Ethotrace::Error)
  end
end
