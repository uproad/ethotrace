# frozen_string_literal: true

RSpec.describe Ethotrace do
  it "has a version number" do
    expect(Ethotrace::VERSION).not_to be_nil
  end

  describe "SCHEMA_VERSION" do
    it "is defined as an integer (stable cross-gem contract)" do
      expect(Ethotrace::SCHEMA_VERSION).to be_a(Integer)
    end

    it "is pinned to schema v1" do
      expect(Ethotrace::SCHEMA_VERSION).to eq(1)
    end
  end
end
