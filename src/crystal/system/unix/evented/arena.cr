# Generational Arena.
#
# Allocates a `Slice` of `T` through `mmap`. `T` is supposed to be a struct, so
# it can be embedded right into the memory region.
#
# The arena allocates objects `T` at a predefined index. The object iself is
# uninitialized (outside of having its memory initialized to zero). The object
# can be allocated and later retrieved using the generation index
# (Arena::Index) that contains both the actual index (Int32) and the generation
# number (UInt32). Deallocating the object increases the generation number,
# which allows the object to be reallocated later on. Trying to retrieve the
# allocation using the generation index will fail if the generation number
# changed (it's a new allocation).
#
# This arena isn't generic as it won't keep a list of free indexes. It assumes
# that something else will maintain the uniqueness of indexes and reuse indexes
# as much as possible instead of growing.
#
# For example this arena is used to hold `Crystal::Evented::PollDescriptor`
# allocations for all the fd in a program, where the fd is used as the index.
# They're unique to the process and the OS always reuses the lowest fd numbers
# before growing.
#
# Thread safety: the memory region is pre-allocated (up to capacity) using mmap
# (virtual allocation) and pointers are never invalidated. Individual
# (de)allocations of objects are protected with a fine grained lock.
#
# Guarantees: `mmap` initializes the memory to zero, which means `T` objects are
# initialized to zero by default, then `#free` will also clear the memory, so
# the next allocation shall be initialized to zero, too.
#
# TODO: instead of the mmap that must preallocate a fixed chunk of virtual
# memory, we could allocate individual blocks of memory, then access the actual
# block at `index % size`. Pointers would still be valid (as long as the block
# isn't collected). We wouldn't have to worry about maximum capacity, we could
# still allocate blocks discontinuously & collect unused blocks during GC
# collections.
class Crystal::Evented::Arena(T)
  INVALID_INDEX = Index.new(-1, 0)

  struct Index
    def initialize(index : Int32, generation : UInt32)
      @data = (index.to_i64! << 32) | generation.to_u64!
    end

    def initialize(@data : Int64)
    end

    def initialize(data : UInt64)
      @data = data.to_i64!
    end

    # Returns the generation number.
    def generation : UInt32
      @data.to_u32!
    end

    # Returns the actual index.
    def index : Int32
      (@data >> 32).to_i32!
    end

    def to_i64 : Int64
      @data
    end

    def to_u64 : UInt64
      @data.to_u64!
    end

    def valid? : Bool
      @data >= 0
    end
  end

  struct Entry(T)
    @lock = SpinLock.new # protects parallel allocate/free calls
    property? allocated = false
    property generation = 0_u32
    @object = uninitialized T

    def pointer : Pointer(T)
      pointerof(@object)
    end

    def free : Nil
      @generation &+= 1_u32
      @allocated = false
      pointer.clear(1)
    end
  end

  @buffer : Slice(Entry(T))

  {% unless flag?(:preview_mt) %}
    # Remember the maximum allocated fd ever;
    #
    # This is specific to `EventLoop#after_fork` that needs to iterate the arena
    # for registered fds in epoll/kqueue to re-add them to the new epoll/kqueue
    # instances. Without this upper limit we'd iterate the whole arena which
    # would lead the kernel to try and allocate the whole mmap in physical
    # memory (instead of virtual memory) which would at best be a waste, and a
    # worst fill the memory (e.g. unlimited open files).
    @maximum = 0
  {% end %}

  def initialize(capacity : Int32)
    pointer = self.class.mmap(LibC::SizeT.new(sizeof(Entry(T))) * capacity)
    @buffer = Slice.new(pointer.as(Pointer(Entry(T))), capacity)
  end

  protected def self.mmap(bytesize)
    flags = LibC::MAP_PRIVATE | LibC::MAP_ANON
    prot = LibC::PROT_READ | LibC::PROT_WRITE

    pointer = LibC.mmap(nil, bytesize, prot, flags, -1, 0)
    System.panic("mmap", Errno.value) if pointer == LibC::MAP_FAILED

    {% if flag?(:linux) %}
      LibC.madvise(pointer, bytesize, LibC::MADV_NOHUGEPAGE)
    {% end %}

    pointer
  end

  def finalize
    LibC.munmap(@buffer.to_unsafe, @buffer.bytesize)
  end

  # Yields and allocates the object at *index* unless already allocated.
  # Returns a pointer to the object at *index* and the generation index.
  #
  # Permits two threads to allocate the same object in parallel yet only allow
  # one to initialize it; the other one will silently receive the pointer and
  # the generation index.
  #
  # There are no generational checks.
  # Raises if *index* is out of bounds.
  def lazy_allocate(index : Int32, &) : {Pointer(T), Index}
    entry = at(index)

    entry.value.@lock.sync do
      pointer = entry.value.pointer
      gen_index = Index.new(index, entry.value.generation)

      unless entry.value.allocated?
        {% unless flag?(:preview_mt) %}
          @maximum = index if index > @maximum
        {% end %}

        entry.value.allocated = true
        yield pointer, gen_index
      end

      {pointer, gen_index}
    end
  end

  # Returns a pointer to the object previously allocated at *index*.
  #
  # Raises if the object isn't allocated.
  # Raises if the generation has changed (i.e. the object has been freed then reallocated).
  # Raises if *index* is negative.
  def get(index : Index) : Pointer(T)
    entry = at(index)
    entry.value.pointer
  end

  # Returns a pointer to the object previously allocated at *index*.
  # Returns `nil` if the object isn't allocated or the generation has changed.
  #
  # Raises if *index* is negative.
  def get?(index : Index) : Pointer(T)?
    if entry = at?(index)
      entry.value.pointer
    end
  end

  # Yields the object previously allocated at *index* then releases it. Does
  # nothing if the object isn't allocated or the generation has changed.
  #
  # Raises if *index* is negative.
  def free(index : Index, &) : Nil
    return unless entry = at?(index.index)

    entry.value.@lock.sync do
      return unless entry.value.allocated?
      return unless entry.value.generation == index.generation
      begin
        yield entry.value.pointer
      ensure
        entry.value.free
      end
    end
  end

  private def at(index : Index) : Pointer(Entry(T))
    entry = at(index.index)
    unless entry.value.allocated?
      raise RuntimeError.new("#{self.class.name}: object not allocated at index #{index.index}")
    end
    unless entry.value.generation == index.generation
      raise RuntimeError.new("#{self.class.name}: object generation changed at index #{index.index} (#{index.generation} => #{entry.value.generation})")
    end
    entry
  end

  private def at?(index : Index) : Pointer(Entry(T))?
    return unless entry = at?(index.index)
    return unless entry.value.allocated?
    return unless entry.value.generation == index.generation
    entry
  end

  private def at(index : Int32) : Pointer(Entry(T))
    (@buffer + index).to_unsafe
  end

  private def at?(index : Int32) : Pointer(Entry(T))?
    if 0 <= index < @buffer.size
      @buffer.to_unsafe + index
    end
  end

  {% unless flag?(:preview_mt) %}
    # Iterates all allocated objects, yields the actual index as well as the
    # generation index.
    def each(&) : Nil
      pointer = @buffer.to_unsafe

      0.upto(@maximum) do |index|
        entry = pointer + index

        if entry.value.allocated?
          yield index, Index.new(index, entry.value.generation)
        end
      end
    end
  {% end %}
end
