# # helpers

OUTPUT = File.open(File::NULL)

# OUTPUT = STDOUT

def gc_stats
  5.times { GC.collect }
  stats = GC.stats
  {
    stats.heap_size.humanize_bytes,
    stats.free_bytes.humanize_bytes,
  }.join(STDOUT, ' ')
end

def bnch(msg, &)
  LibC.getrusage(LibC::RUSAGE_SELF, out before)
  elapsed = Time.measure { yield }
  LibC.getrusage(LibC::RUSAGE_SELF, out after)

  print msg
  print ' '
  gc_stats
  print ' '
  {
    elapsed.total_microseconds.to_i,
    # ((after.ru_utime.tv_sec * 1_000_000 + after.ru_utime.tv_usec) - (before.ru_utime.tv_sec * 1_000_000 + before.ru_utime.tv_usec)),
    ((after.ru_stime.tv_sec * 1_000_000 + after.ru_stime.tv_usec) - (before.ru_stime.tv_sec * 1_000_000 + before.ru_stime.tv_usec)),
    ((after.ru_maxrss - before.ru_maxrss) * 1024).humanize_bytes,
    after.ru_minflt - before.ru_minflt,
    # after.ru_majflt - before.ru_majflt,
    after.ru_nvcsw - before.ru_nvcsw,
    # after.ru_nivcsw - before.ru_nivcsw,
  }.join(STDOUT, ' ')
  puts
end

# # functions to bench different situations

@[NoInline]
def foo(i)
  if i < 4
    foo(i + 1)
  else
    raise "oops"
  end
end

@[NoInline]
def test(i, msg)
  bnch(msg) do
    begin
      foo(0)
    rescue exception
      OUTPUT.puts exception.pretty_inspect
      OUTPUT.puts exception.backtrace.pretty_inspect
    end
  end
end

@[NoInline]
def test2
  foo(5)
end

@[NoInline]
def test3
  test2
end

if ENV.has_key?("dw_stats")
  Exception::CallStack.load_debug_info
  exit 0
end

# # actual benchmarks
puts "BENCH GC_HEAP GC_FREE RTIME STIME MAXRSS MINFLT C/S"

bnch("PRELOAD") do
  Exception::CallStack.load_debug_info
end

[
  "EMPTY",
  "FULL",
].each do |msg|
  test(0, msg)
end

bnch("PARTIAL:1") do
  begin
    foo(5)
  rescue exception
    OUTPUT.puts exception.pretty_inspect
    OUTPUT.puts exception.backtrace.pretty_inspect
  end
end

bnch("PARTIAL:3") do
  begin
    test3
  rescue exception
    OUTPUT.puts exception.pretty_inspect
    OUTPUT.puts exception.backtrace.pretty_inspect
  end
end
