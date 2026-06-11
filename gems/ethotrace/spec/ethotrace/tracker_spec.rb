# frozen_string_literal: true

RSpec.describe Ethotrace::Tracker do
  # 各 example の独立性を保つため、スタックを必ず破棄する。
  after { described_class.reset }

  def begin_call(name:, owner: "Order", kind: :instance, site: nil)
    described_class.begin_call(owner: owner, name: name, kind: kind, site: site)
  end

  describe ".begin_call" do
    it "returns a CallContext built from the descriptor" do
      ctx = begin_call(owner: "Order", name: :total, kind: :instance,
                       site: { path: "order.rb", line: 1 })
      expect(ctx).to be_a(Ethotrace::CallContext)
      expect([ctx.owner, ctx.name, ctx.kind, ctx.site])
        .to eq(["Order", "total", :instance, { path: "order.rb", line: 1 }])
    end

    it "pushes the context onto the call stack" do
      ctx = begin_call(name: :total)
      expect(described_class.call_stack).to eq([ctx])
      expect(described_class.current).to be(ctx)
    end

    it "stacks nested calls with the deepest as current" do
      outer = begin_call(name: :outer)
      inner = begin_call(name: :inner)
      expect(described_class.call_stack).to eq([outer, inner])
      expect(described_class.current).to be(inner)
    end
  end

  describe ".end_call" do
    it "pops the matching context and returns it" do
      ctx = begin_call(name: :total)
      expect(described_class.end_call(ctx)).to be(ctx)
      expect(described_class.active?).to be(false)
    end

    it "unwinds nested calls in LIFO order" do
      outer = begin_call(name: :outer)
      inner = begin_call(name: :inner)
      described_class.end_call(inner)
      expect(described_class.current).to be(outer)
      described_class.end_call(outer)
      expect(described_class.active?).to be(false)
    end

    it "discards inner frames left behind on a mismatched unwind" do
      outer = begin_call(name: :outer)
      begin_call(name: :inner) # 取り残された内側フレーム
      described_class.end_call(outer)
      # outer 以降をまとめて破棄し、スタックをリークさせない。
      expect(described_class.active?).to be(false)
    end

    it "is a no-op when the context is no longer on the stack" do
      ctx = begin_call(name: :total)
      described_class.end_call(ctx)
      expect { described_class.end_call(ctx) }.not_to(change { described_class.call_stack.dup })
    end
  end

  describe ".current / .active?" do
    it "are nil/false with no active call" do
      expect(described_class.current).to be_nil
      expect(described_class.active?).to be(false)
    end
  end

  describe "Thread/Fiber isolation" do
    it "gives each thread an independent stack" do
      begin_call(name: :total)
      other = Thread.new { described_class.active? }.value
      expect(other).to be(false)
    end

    it "gives each fiber an independent stack" do
      begin_call(name: :total)
      in_fiber = Fiber.new { Fiber.yield(described_class.active?) }.resume
      # Thread.current[] は Fiber-local なので、別 Fiber は空のスタックを見る。
      expect(in_fiber).to be(false)
    end
  end

  describe ".record_escape" do
    let(:exception) { KeyError.new("missing") }

    it "attributes the first wrapped frame an exception escapes as direct" do
      ctx = begin_call(owner: "C", name: :c)
      described_class.record_escape(ctx, exception)
      expect(ctx.to_observation[:errors])
        .to eq([{ class: "KeyError", origin: "direct", from: nil }])
    end

    it "attributes an outer frame as inherited from the deeper callee" do
      callee = begin_call(owner: "C", name: :c)
      caller_ctx = begin_call(owner: "B", name: :b)
      # 例外は深いフレーム(callee)を先に通り、次に外側(caller)を通る。
      described_class.record_escape(callee, exception)
      described_class.record_escape(caller_ctx, exception)
      expect(caller_ctx.to_observation[:errors])
        .to eq([{ class: "KeyError", origin: "inherited", from: "C#c" }])
    end

    it "uses dot notation for a singleton callee in `from`" do
      callee = begin_call(owner: "C", name: :build, kind: :singleton)
      caller_ctx = begin_call(owner: "B", name: :b)
      described_class.record_escape(callee, exception)
      described_class.record_escape(caller_ctx, exception)
      expect(caller_ctx.to_observation[:errors].first[:from]).to eq("C.build")
    end

    it "treats a different exception object as a fresh direct escape" do
      first = begin_call(owner: "C", name: :c)
      second = begin_call(owner: "B", name: :b)
      described_class.record_escape(first, exception)
      described_class.record_escape(second, RuntimeError.new("other"))
      expect(second.to_observation[:errors].first).to include(origin: "direct", from: nil)
    end
  end

  describe ".record_effect" do
    it "attributes the effect to every active frame (deepest direct, others inherited)" do
      outer = begin_call(owner: "A", name: :a)
      middle = begin_call(owner: "B", name: :b)
      inner = begin_call(owner: "C", name: :c)

      described_class.record_effect("env.read", write: false, key: "TAX_RATE")

      expect(inner.to_observation[:requirements].first)
        .to include(kind: "env.read", direct: true, from: nil, detail: { key: "TAX_RATE" })
      expect(middle.to_observation[:requirements].first).to include(direct: false, from: "C#c")
      expect(outer.to_observation[:requirements].first).to include(direct: false, from: "B#b")
    end

    it "passes write and detail through" do
      ctx = begin_call(owner: "A", name: :a)
      described_class.record_effect("io.write", write: true, path: "/tmp/x", mode: "w")
      expect(ctx.to_observation[:requirements].first)
        .to include(write: true, detail: { path: "/tmp/x", mode: "w" })
    end

    it "is a no-op when no method is being observed" do
      expect { described_class.record_effect("time.read", write: false) }.not_to raise_error
      expect(described_class.active?).to be(false)
    end
  end

  describe ".reset" do
    it "clears the current stack" do
      begin_call(name: :total)
      described_class.reset
      expect(described_class.active?).to be(false)
    end

    it "clears the exception attribution state" do
      ctx = begin_call(owner: "C", name: :c)
      exception = KeyError.new
      described_class.record_escape(ctx, exception)
      described_class.reset
      # reset 後は同じ例外でも伝播元の記憶が消え、direct 扱いに戻る。
      fresh = begin_call(owner: "B", name: :b)
      described_class.record_escape(fresh, exception)
      expect(fresh.to_observation[:errors].first).to include(origin: "direct")
    end
  end
end
