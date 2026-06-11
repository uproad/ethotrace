# frozen_string_literal: true

RSpec.describe Ethotrace::ArgumentTable do
  after { described_class.reset }

  def context(owner: "Order", name: :total, kind: :instance)
    Ethotrace::CallContext.new(owner: owner, name: name, kind: kind)
  end

  describe ".track" do
    it "records classes_seen and parameter names on the context" do
      ctx = context
      described_class.track(ctx, [[1, 2], "x"], %i[items label])
      expect(ctx.to_observation[:params]).to contain_exactly(
        a_hash_including(position: 0, name: "items", classes_seen: ["Array"]),
        a_hash_including(position: 1, name: "label", classes_seen: ["String"])
      )
    end

    it "registers trackable arguments for lookup by object_id" do
      ctx = context
      arg = [1, 2]
      described_class.track(ctx, [arg])
      expect(described_class.lookup(arg.object_id)).to eq([[ctx, 0]])
    end

    it "lets the same object be owned by multiple active contexts" do
      shared = +"shared"
      outer = context(owner: "A")
      inner = context(owner: "B")
      described_class.track(outer, [shared])
      described_class.track(inner, [shared])
      expect(described_class.lookup(shared.object_id))
        .to contain_exactly([outer, 0], [inner, 0])
    end

    it "does not track value-shared immediates but still records their class" do
      ctx = context
      described_class.track(ctx, [42, :sym, 3.14, nil, true])
      expect(described_class.lookup(42.object_id)).to eq([])
      expect(ctx.to_observation[:params].map { |p| p[:classes_seen] })
        .to eq([["Integer"], ["Symbol"], ["Float"], ["NilClass"], ["TrueClass"]])
    end

    it "ignores objects without an object_id (e.g. BasicObject) without raising" do
      ctx = context
      expect { described_class.track(ctx, [BasicObject.new]) }.not_to raise_error
    end

    it "is not fooled by an argument that overrides #object_id" do
      ctx = context
      liar = Object.new
      def liar.object_id = 999_999
      described_class.track(ctx, [liar])
      real_id = Object.instance_method(:object_id).bind_call(liar)
      expect(described_class.lookup(real_id)).to eq([[ctx, 0]])
      expect(described_class.lookup(999_999)).to eq([])
    end
  end

  describe ".untrack" do
    it "removes only the given context's registrations" do
      shared = +"shared"
      outer = context(owner: "A")
      inner = context(owner: "B")
      described_class.track(outer, [shared])
      described_class.track(inner, [shared])
      described_class.untrack(inner)
      expect(described_class.lookup(shared.object_id)).to eq([[outer, 0]])
    end

    it "drops the table entry once no context owns the object" do
      arg = [1]
      ctx = context
      described_class.track(ctx, [arg])
      described_class.untrack(ctx)
      expect(described_class.lookup(arg.object_id)).to eq([])
    end

    it "is a no-op for a context that registered nothing" do
      expect { described_class.untrack(context) }.not_to raise_error
    end
  end

  describe "Thread/Fiber isolation" do
    it "keeps tables independent across threads" do
      arg = [1]
      described_class.track(context, [arg])
      other = Thread.new { described_class.lookup(arg.object_id) }.value
      expect(other).to eq([])
    end
  end
end
