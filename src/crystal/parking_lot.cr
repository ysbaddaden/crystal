# Crystal implementation heavily influenced by the "parking_lot" Rust crate
# written by Amanieu d'Antras, itself a port of WTF::ParkingLot in Webkit,
# itself inspired by Linux futexes.
#
# References:
# - <https://github.com/Amanieu/parking_lot>
# - <https://webkit.org/blog/6161/locking-in-webkit/>

require "crystal/pointer_linked_list"

module Crystal
  # :nodoc:
  #
  # The parking lot allows a fiber to wait on a Pointer until woken up, similar
  # to Linux futexes. Avoids internalizing a wait queue in every sync primitive,
  # and instead use an external queue stored in a global hash table, identified
  # by a Pointer.
  #
  # The pointer is simply an unique key to distinguish each queue and can point
  # to anything, from an UInt8* to any Struct* or Reference. There is no atomic
  # check of the pointed value but a validation callback instead. See `.wait`.
  #
  # The parking lot can be used to implement a TinyMutex that only takes a
  # single UInt8, a TinyRWLock out of an UInt32, or just to have a simple wait
  # logic with only two methods, `.wait` and `.wake`. This can help to implement
  # micro-locks, or when a lock shall barely be contended (if ever) and will
  # often never have to wait, but some corner cases may have to.
  #
  # The internal hash table is implemented using separate chaining. Each bucket
  # is individually lockable, and queues that happen to be on the same bucket
  # are mixed together in the bucket's linked-list. There should always be
  # enough buckets that not too many active queues shall end up into the same
  # bucket (unless very unlucky).
  #
  # The internal hash table size at any moment is the largest number of
  # concurrent fibers that have been waiting at the same time. For example if
  # you have 128 active fibers but only 13 waited at the same moment, then the
  # table size will be 13 × LOAD_FACTOR elevated to the next power of two, that
  # is 32 buckets for a load factor of 2.
  #
  # TODO: we could shrink, the @@concurrency atomic can be used to detect that
  # the load factor is too high, just the same as for growing, though it might
  # lead to a grow-shrink loop. We can define a large load factor such as 5 or
  # 10 to avoid this, so it's easy to grow, but harder to shrink.
  module ParkingLot
    # :nodoc:
    DEFAULT_SIZE = 4

    # :nodoc:
    #
    # Threads could use a load factor of 3 because they should be kept to a
    # reasonable number (and threads waiting in parallel even lower) but fibers
    # can grow more out of control, so we use a lower load factor.
    LOAD_FACTOR = 2

    # :nodoc:
    #
    # The fiber-local data used to insert a Fiber with a key address into a
    # bucket list of the hash table. Allocating an instance may lead to grow the
    # hash table.
    #
    # OPTIMIZE: allocate once per fiber, dispose during run finalization (?)
    struct FiberData
      @@concurrency = Atomic(Int32).new(0)

      getter fiber : Fiber
      property key : Void*

      include PointerLinkedList::Node

      def initialize(@fiber : Fiber, @key = Pointer(Void).null)
        concurrency = @@concurrency.add(1, :relaxed) + 1
        ParkingLot.grow(concurrency)
      end

      def dispose : Nil
        @@concurrency.sub(1, :relaxed)
      end

      def enqueue : Nil
        @key = Pointer(Void).null
        @fiber.enqueue
      end
    end

    # :nodoc:
    #
    # Represents an individual bucket in the hash table.
    struct Bucket
      @mutex = Thread::Mutex.new
      @list = PointerLinkedList(FiberData).new

      def lock : Nil
        @mutex.lock
      end

      def unlock : Nil
        @mutex.unlock
      end

      def unsafe_each(& : FiberData* ->) : Nil
        @list.each { |data| yield data }
      end

      def unsafe_push(data : FiberData*) : Nil
        @list.push(data)
      end

      def unsafe_delete(data : FiberData*) : Nil
        @list.delete(data)
      end
    end

    # :nodoc:
    #
    # A separate chaining hash table, where each slot of the bucket array is an
    # individually lockable doubly linked-list.
    class HashTable
      getter size : Int32
      getter bitshift : Int32
      getter buckets : Pointer(Bucket)

      def initialize(size : Int32)
        @size = Math.pw2ceil(size.clamp(1..) * LOAD_FACTOR)
        @bitshift = {{ flag?(:bits32) ? 32 : 64 }} - @size.trailing_zeros_count
        @buckets = Pointer(Bucket).malloc(@size)
        @size.times { |i| @buckets[i] = Bucket.new }
      end

      def needs_to_grow?(size : Int32) : Bool
        Math.pw2ceil(size.clamp(1..) * LOAD_FACTOR) > @size
      end

      def lock(& : ->) : Nil
        each_bucket(&.value.lock)
        begin
          yield
        ensure
          each_bucket(&.value.unlock)
        end
      end

      def bucket(key : Pointer) : Bucket*
        @buckets + hash(key.as(Void*))
      end

      def unsafe_each(& : FiberData* ->) : Nil
        each_bucket do |bucket|
          bucket.value.unsafe_each { |data| yield data }
        end
      end

      def unsafe_rehash(new_table : self) : Nil
        each_bucket do |bucket|
          bucket.value.unsafe_each do |data|
            bucket.value.unsafe_delete(data)
            new_table.unsafe_push(data)
          end
        end
      end

      def unsafe_push(data : FiberData*) : Nil
        bucket = bucket(data.value.key)
        bucket.value.unsafe_push(data)
      end

      private def each_bucket(&)
        bucket = @buckets
        limit = @buckets + size

        while bucket < limit
          yield bucket
          bucket += 1
        end
      end

      private def hash(key : Void*)
        {% if flag?(:bits32) %}
          (key.address.to_u32! & 0x9E3779B9_u32) >> @bitshift
        {% else %}
          (key.address & 0x9E3779B97F4A7C15_u64) >> @bitshift
        {% end %}
      end
    end

    @@hashtable = Atomic(HashTable).new(HashTable.new(DEFAULT_SIZE))

    protected def self.grow(size : Int32) : Nil
      loop do
        hashtable = @@hashtable.lazy_get
        return unless hashtable.needs_to_grow?(size)

        # lock everything (must own every bucket)
        hashtable.lock do
          # we must verify that another thread didn't grow the table while we
          # acquired the locks; we use an atomic to force-reload the pointer
          if hashtable.same?(@@hashtable.get(:relaxed))
            if hashtable.needs_to_grow?(size)
              Crystal.trace :sched, "parking_lot.grow", size: size

              # allocate new table, then rehash
              new_table = HashTable.new(size)
              hashtable.unsafe_rehash(new_table)

              # we can update the reference, no need for an atomic: we locked
              # everything in the old table (and thus own it) and the locks will
              # deal with memory ordering
              @@hashtable.lazy_set(new_table)
            end

            return
          end
        end
      end
    end

    # Adds the calling fiber to the queue associated with *key*, and waits until
    # the fiber is woken by a call to `.wake`.
    #
    # The *validate* block will be called after acquiring the lock and before
    # adding the calling fiber to the queue; if the block evaluates to false the
    # operation is aborted and the method returns immediately without blocking.
    @[AlwaysInline]
    def self.wait(key : Pointer | Reference, &validate : -> Bool) : Nil
      wait_impl(key.as(Void*), &validate)
    end

    @[NoInline]
    protected def self.wait_impl(key : Void*, &validate : -> Bool) : Nil
      data = FiberData.new(Fiber.current, key.as(Void*))

      begin
        lock_bucket(key) do |bucket|
          return unless validate.call
          Crystal.trace :sched, "parking_lot.wait", m: key.as(Atomic(UInt8)*).value.get(:relaxed)
          bucket.value.unsafe_push(pointerof(data))
        end

        Fiber.suspend
      ensure
        data.dispose
      end
    end

    # Removes and enqueues *count* fibers from the queue associated with *key*.
    # Defaults to waking every fibers in the queue. Does nothing if the queue is
    # empty.
    #
    # The *unpark* callback will be called before unlocking and before the
    # fibers are enqueued; its argument are in order: the number of woken fibers
    # (may be 0, 1 or more up to *count*), followed by  a boolean telling if one
    # or more fibers are still in the queue associated with *key* (i.e. the
    # queue isn't empty).
    @[AlwaysInline]
    def self.wake(key : Pointer | Reference, *, count : Int32 = Int32::MAX, &unpark : (Int32, Bool) ->) : Nil
      wake_impl(key.as(Void*), count, &unpark) if count > 0
    end

    @[NoInline]
    protected def self.wake_impl(key : Void*, count : Int32, &unpark : (Int32, Bool) ->) : Nil
      list = PointerLinkedList(FiberData).new
      has_waiting_fibers = false
      size = 0

      lock_bucket(key) do |bucket|
        bucket.value.unsafe_each do |data|
          if data.value.key == key.as(Void*)
            if size < count
              bucket.value.unsafe_delete(data)
              list.push(data)
              size += 1
            else
              has_waiting_fibers = true
              break
            end
          end
        end

        unpark.call(size, has_waiting_fibers)
      end

      list.consume_each do |data|
        Crystal.trace :sched, "parking_lot.wake", fiber: data.value.fiber, m: key.as(Atomic(UInt8)*).value.get(:relaxed)
        data.value.enqueue
      end
    end

    private def self.lock_bucket(key : Pointer, & : Pointer(Bucket) ->) : Nil
      loop do
        hashtable = @@hashtable.lazy_get

        bucket = hashtable.bucket(key)
        bucket.value.lock

        begin
          # we must verify that another thread didn't grow the table while we
          # acquired the lock; we use an atomic to force-reload the pointer
          if hashtable.same?(@@hashtable.get(:relaxed))
            yield bucket
            break
          end
        ensure
          bucket.value.unlock
        end
      end
    end
  end
end
