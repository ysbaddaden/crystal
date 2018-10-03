# :nodoc:
class Crystal::Scheduler
  # :nodoc:
  #
  # Crystal only accepts simple primitives such as Atomic(T). This struct wraps
  # a 64-bit struct as an Atomic(UInt64) and transparently casts from T and
  # UInt64.
  struct AtomicRef8(T)
    def initialize(value : T)
      # TODO: raise a compile-time error unless sizeof(T) == 8
      @atomic = Atomic(UInt64).new(value.unsafe_as(UInt64))
    end

    def get : T
      @atomic.get.unsafe_as(T)
    end

    def set(value : T)
      @atomic.set(value.unsafe_as(UInt64))
    end

    def compare_and_set(cmp : T, value : T) : Bool
      _, success = @atomic.compare_and_set(cmp.unsafe_as(UInt64), value.unsafe_as(UInt64))
      success
    end
  end

  # :nodoc:
  #
  # Thread-safe non-blocking queue for work-stealing schedulers.
  #
  # Based on:
  #
  # - "Scheduling Multithreaded Computations by Work Stealing" (2001) by
  #   Nimar S. Arora, Robert D. Blumofe and C. Greg Plaxton.
  #
  # - "Verification of a Concurrent Deque Implementation" (1999) by
  #   Robert D. Blumofe, C. Greg Plaxton and Sandip Ray.
  #
  # The queue has the following assumptions:
  #
  # - Only the owner thread will push to the bottom of the queue (never
  #   call concurrently);
  #
  # - Only the owner thread will pop from the bottom of the queue (never called
  #   concurrently, and limited concurrency with pop top);
  #
  # - Only other threads will pop from the top of the queue (expected to be
  #   called concurrently):
  #
  # - The underlying array is supposed to be infinite.
  #
  # Read the above papers for more details.
  class Queue(T)
    # :nodoc:
    record Age, tag : Int32, top : Int32

    # :nodoc:
    SIZE = Int32::MAX

    def initialize
      @bot = Atomic(Int32).new(0)
      @age = AtomicRef8(Age).new(Age.new(0, 0))

      # initializes the "infinite" array, using mmap so memory pages will only
      # be allocated when accessed (if ever):
      prot = LibC::PROT_READ | LibC::PROT_WRITE
      flags = LibC::MAP_ANONYMOUS | LibC::MAP_PRIVATE
      ptr = LibC.mmap(nil, SIZE, prot, flags, -1, 0)
      raise Errno.new("mmap") if ptr == LibC::MAP_FAILED
      @deq = ptr.as(Fiber*)
    end

    def free
      LibC.munmap(@deq, SIZE)
    end

    # Pushes an item to the tail of the queue. Not thread-safe and must be
    # called from the thread that owns the queue.
    def push_bottom(item : T) : Nil
      bot = @bot.get
      @deq[bot] = item
      @bot.set(bot + 1)
    end

    # Pops an item from the tail of the queue. Not thread-safe and must be
    # called from the thread that owns the queue.
    def pop_bottom : T?
      bot = @bot.get
      return if bot == 0

      bot -= 1
      @bot.set(bot)

      item = @deq[bot]
      old_age = @age.get
      return item if bot > old_age.top

      # queue has been emptied (reset bottom to zero):
      @bot.set(0)
      new_age = Age.new(old_age.tag + 1, 0)

      if bot == old_age.top
        if @age.compare_and_set(old_age, new_age)
          return item
        end
      end

      @age.set(new_age)
      nil
    end

    # Pops an item from the head of the queue. Thread-safe and should be called
    # from threads that don't own the queue (i.e. stealing threads).
    def pop_top : T?
      old_age = @age.get
      bot = @bot.get
      return if bot <= old_age.top

      item = @deq[old_age.top]
      new_age = Age.new(old_age.tag, old_age.top + 1)

      if @age.compare_and_set(old_age, new_age)
        return item
      end
    end

    # Lazily returns the queue size. It may be equal or slightly more or less
    # than the actual size.
    def lazy_size : Int32
      bot = @bot.get
      age = @age.get
      bot - age.top
    end
  end
end
