require "c/sys/mman"
require "thread/linked_list"

# Load the arch-specific methods to create a context and to swap from one
# context to another one. There are two methods: `Fiber#makecontext` and
# `Fiber.swapcontext`.
#
# - `Fiber.swapcontext(current_context : Fiber::Context*, new_context : Fiber::Context*)
#
#   A fiber context switch in Crystal is achieved by calling a symbol (which
#   must never be inlined) that will push the callee-saved registers (sometimes
#   FPU registers and others) on the stack, saving the current stack pointer at
#   location pointed by `current_stack_ptr` (the current fiber is now paused)
#   then loading the `dest_stack_ptr` pointer into the stack pointer register
#   and popping previously saved registers from the stack. Upon return from the
#   symbol the new fiber is resumed since we returned/jumped to the calling
#   symbol.
#
#   Details are arch-specific. For example:
#   - which registers must be saved, the callee-saved are sometimes enough (X86)
#     but some archs need to save the FPU register too (ARMHF);
#   - a simple return may be enough (X86), but sometimes an explicit jump is
#     required to not confuse the stack unwinder (ARM);
#   - and more.
#
#   For the initial resume, the register holding the first parameter must be set
#   (see makecontext below) and thus must also be saved/restored.
#
# - `Fiber#makecontext(stack_ptr : Void*, fiber_main : Fiber ->))`
#
#   `makecontext` is responsible to reserve and initialize space on the stack
#   for the initial context and to save the initial `@context.stack_top`
#   pointer. The first time a fiber is resumed, the `fiber_main` proc must be
#   called, passing `self` as its first argument.
require "./fiber/*"

# :nodoc:
@[NoInline]
fun _fiber_get_stack_top : Void*
  dummy = uninitialized Int32
  pointerof(dummy).as(Void*)
end

class Fiber
  # :nodoc:
  #
  # The arch-specific make/swapcontext assembly relies on the Fiber::Context
  # struct and expects the following layout. Avoid moving the struct properties
  # as it would require to update all the make/swapcontext implementations.
  @[Extern]
  struct Context
    property resumable : LibC::Long
    property stack_top : Void*

    def initialize
      @resumable = 0
      @stack_top = Pointer(Void).null
    end
  end

  STACK_SIZE = 8 * 1024 * 1024

  include Thread::LinkedList(Fiber)

  @stack : Void*
  @context = Context.new
  protected property stack_bottom : Void*
  @resume_event : Crystal::Event?
  property name : String?

  def resumable? : Bool
    @context.resumable == 1
  end

  def running? : Bool
    @context.resumable == 0
  end

  def initialize(@name : String? = nil, &@proc : ->)
    @stack = Fiber.allocate_stack
    @stack_bottom = @stack + STACK_SIZE

    fiber_main = ->(f : Fiber) { f.run }

    # ???
    stack_ptr = @stack_bottom - sizeof(Void*)

    # align the stack pointer to 16 bytes
    stack_ptr = Pointer(Void*).new(stack_ptr.address & ~0x0f_u64)

    makecontext(stack_ptr, fiber_main)

    Fiber.push(self)
  end

  # :nodoc:
  def initialize(@name = "main")
    @proc = Proc(Void).new { }
    @stack = Pointer(Void).null
    @context.stack_top = _fiber_get_stack_top
    @stack_bottom = GC.stack_bottom

    Fiber.push(self)
  end

  protected def self.allocate_stack
    if pointer = stack_pool.pop?
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
    Fiber.stack_pool << @stack

    # Remove the current fiber from the linked list
    Fiber.delete(self)

    # Delete the resume event if it was used by `yield` or `sleep`
    @resume_event.try &.free

    Crystal::Scheduler.reschedule
  end

  def self.current
    Crystal::Scheduler.current_fiber
  end

  def resume : Nil
    Crystal::Scheduler.resume(self)
  end

  # :nodoc:
  def resume_event
    @resume_event ||= Crystal::EventLoop.create_resume_event(self)
  end

  def self.yield
    Crystal::Scheduler.yield
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

  # Push the used section of the stack
  protected def push_gc_roots
    GC.push_stack @context.stack_top, @stack_bottom
  end

  # :nodoc:
  #
  # Registers the current fiber stack to the GC as the stack that the current
  # thread is running.
  def register_gc_stack : Nil
    GC.stack_bottom = @stack_bottom
    # thread = Thread.current
    # GC.register_altstack(thread.stack_bottom, thread.stack_size,  @stack_bottom, STACK_SIZE)
  end

  # pushes the stack of pending fibers when the GC wants to collect memory:
  GC.before_collect do
    Fiber.unsafe_each do |fiber|
      fiber.push_gc_roots unless fiber.running?
    end
  end
end
