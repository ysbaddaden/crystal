require "spec"
require "./spec_helper"

@[NoInline]
private def gc_churn
  10_000.times { Bytes.new(1024, 42) }
  GC.collect
end

@[NoInline]
private def gc_check_live_stack_roots
  bytes = Bytes.new(1024, 123)
  4.times do
    gc_churn
    bytes.all? { |byte| byte == 123 }.should be_true
  end
end

@[NoInline]
private def gc_check_mixed_union_roots(number : Int64)
  bytes = number.as(Bytes | Int64)
  string = number.as(String | Int64)
  4.times do
    gc_churn
    if bytes.is_a?(Bytes)
      bytes.all? { |byte| byte == 123 }.should be_true
      bytes = number
    else
      bytes.should eq(number)
      bytes = Bytes.new(1024, 123)
    end
    if string.is_a?(String)
      string.each_byte { |byte| byte.should eq(123) }
      string = number
    else
      string.should eq(number)
      string = String.new(Bytes.new(1024, 123))
    end
  end
end

private class GCFinalizer
  class_getter count = 0

  def finalize
    @@count += 1
  end
end

@[NoInline]
private def gc_allocate_finalizable
  10.times { GCFinalizer.new }
end

describe "GC" do
  it "preserves live allocations across calls that collect" do
    gc_check_live_stack_roots
  end

  it "preserves pointer payloads of mixed unions across collection" do
    gc_check_mixed_union_roots(Random.rand(Int64))
  end

  pending_wasm32 describe: "abort on OOM" do
    it "aborts with an error message when an allocation is too large for the heap" do
      status, _, error = compile_and_run_source <<-CRYSTAL
        GC.max_heap_size = 64_u64 * 1024 * 1024
        GC.malloc(1_u64 << 30)
        CRYSTAL

      status.normal_exit?.should be_true
      status.exit_code.should eq(1)
      error.should contain("Out of memory: failed to allocate 1073741824 bytes")
    end

    it "aborts with an error message when the heap is exhausted" do
      status, _, error = compile_and_run_source <<-CRYSTAL
        GC.max_heap_size = 32_u64 * 1024 * 1024
        bufs = [] of Bytes
        loop do
          bufs << Bytes.new(1024 * 1024)
        end
        CRYSTAL

      status.normal_exit?.should be_true
      status.exit_code.should eq(1)
      error.should contain("Out of memory: failed to allocate")
    end
  end

  it "compiles GC.stats" do
    typeof(GC.stats).should eq(GC::Stats)
  end

  {% unless flag?(:gc_none) %}
    it "raises if calling enable when not disabled" do
      expect_raises(Exception, "GC is not disabled") do
        GC.enable
      end
    end

    it "calls finalizers that return a value" do
      gc_allocate_finalizable
      GC.collect
      GCFinalizer.count.should be > 0
    end
  {% end %}

  it ".stats" do
    GC.stats.should be_a(GC::Stats)
    {% unless flag?(:gc_none) %}
      GC.stats.heap_size.should be > 0
    {% end %}
  end

  it ".prof_stats" do
    GC.prof_stats.should be_a(GC::ProfStats)
  end
end
