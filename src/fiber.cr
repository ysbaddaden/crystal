require "c/sys/mman"
require "./fiber/*"

# :nodoc:
@[NoInline]
fun _fiber_get_stack_top : Void*
  dummy = uninitialized Int32
  pointerof(dummy).as(Void*)
end

class Fiber
  STACK_SIZE = 8 * 1024 * 1024

  @@first_fiber : Fiber? = nil
  @@last_fiber : Fiber? = nil
  @@stack_pool = [] of Void*

  @stack : Void*
  @resume_event : Event::Event?
  @stack_top = Pointer(Void).null
  protected property stack_top : Void*
  protected property stack_bottom : Void*
  protected property next_fiber : Fiber?
  protected property prev_fiber : Fiber?
  property name : String?

  def initialize(@name : String? = nil, &@proc : ->)
    @stack = Fiber.allocate_stack
    @stack_bottom = @stack + STACK_SIZE

    fiber_main = ->(f : Fiber) { f.run }
    stack_ptr = @stack_bottom - sizeof(Void*)
    makecontext(stack_ptr, fiber_main)

    @prev_fiber = nil
    if last_fiber = @@last_fiber
      @prev_fiber = last_fiber
      last_fiber.next_fiber = @@last_fiber = self
    else
      @@first_fiber = @@last_fiber = self
    end
  end

  # :nodoc:
  def initialize
    @proc = Proc(Void).new { }
    @stack = Pointer(Void).null
    @stack_top = _fiber_get_stack_top
    @stack_bottom = GC.stack_bottom
    @name = "main"

    @@first_fiber = @@last_fiber = self
  end

  protected def self.allocate_stack
    if pointer = @@stack_pool.pop?
      return pointer
    end

    flags = LibC::MAP_PRIVATE | LibC::MAP_ANON
    {% if flag?(:openbsd) && !flag?(:"openbsd6.2") %}
      flags |= LibC::MAP_STACK
    {% end %}

    LibC.mmap(nil, Fiber::STACK_SIZE, LibC::PROT_READ | LibC::PROT_WRITE, flags, -1, 0).tap do |pointer|
      raise Errno.new("Cannot allocate new fiber stack") if pointer == LibC::MAP_FAILED

      {% if flag?(:linux) %}
        LibC.madvise(pointer, Fiber::STACK_SIZE, LibC::MADV_NOHUGEPAGE)
      {% end %}

      LibC.mprotect(pointer, 4096, LibC::PROT_NONE)
    end
  end

  # :nodoc:
  def self.stack_pool_collect
    return if @@stack_pool.size == 0
    free_count = @@stack_pool.size > 1 ? @@stack_pool.size / 2 : 1
    free_count.times do
      stack = @@stack_pool.pop
      LibC.munmap(stack, Fiber::STACK_SIZE)
    end
  end

  # :nodoc:
  def run
    @proc.call
  rescue ex
    if name = @name
      STDERR.print "Unhandled exception in spawn(name: #{name}): "
    else
      STDERR.print "Unhandled exception in spawn: "
    end
    ex.inspect_with_backtrace(STDERR)
    STDERR.flush
  ensure
    @@stack_pool << @stack

    # Remove the current fiber from the linked list
    if prev_fiber = @prev_fiber
      prev_fiber.next_fiber = @next_fiber
    else
      @@first_fiber = @next_fiber
    end

    if next_fiber = @next_fiber
      next_fiber.prev_fiber = @prev_fiber
    else
      @@last_fiber = @prev_fiber
    end

    # Delete the resume event if it was used by `yield` or `sleep`
    @resume_event.try &.free

    Crystal::Scheduler.reschedule
  end

  def resume : Nil
    current, Thread.current.current_fiber = Thread.current.current_fiber, self
    GC.stack_bottom = @stack_bottom
    Fiber.swapcontext(pointerof(current.@stack_top), @stack_top)
  end

  def sleep(time : Time::Span)
    event = @resume_event ||= Crystal::EventLoop.create_resume_event(self)
    event.add(time)
    Crystal::Scheduler.reschedule
  end

  def sleep(time : Number)
    sleep(time.seconds)
  end

  def yield
    sleep(0)
  end

  def self.sleep(time)
    Fiber.current.sleep(time)
  end

  def self.yield
    Fiber.current.yield
  end

  def to_s(io)
    io << "#<" << self.class.name << ":0x"
    object_id.to_s(16, io)
    if name = @name
      io << ": " << name
    end
    io << '>'
  end

  def inspect(io)
    to_s(io)
  end

  protected def push_gc_roots
    # Push the used section of the stack
    GC.push_stack @stack_top, @stack_bottom
  end

  @@root = new

  # :nodoc:
  def self.root : self
    @@root
  end

  Thread.current.current_fiber = root

  def self.current : self
    Thread.current.current_fiber
  end

  # This will push all fibers stacks whenever the GC wants to collect some memory
  GC.before_collect do
    fiber = @@first_fiber
    while fiber
      fiber.push_gc_roots unless fiber == Thread.current.current_fiber
      fiber = fiber.next_fiber
    end
  end
end
