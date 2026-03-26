module Crystal
  # :nodoc:
  struct RWLock
    UNLOCKED = 0_u32
    WLOCK    = 1_u32
    RLOCK    = 2_u32
    RMASK    = ~1_u32

    @m = Atomic(UInt32).new(UNLOCKED)

    @[AlwaysInline]
    def write_lock : Nil
      _, success = @m.compare_and_set(UNLOCKED, WLOCK, :acquire, :relaxed)
      write_lock_slow unless success
    end

    @[NoInline]
    private def write_lock_slow : Nil
      backoff_loop do
        m = @m.get(:relaxed)
        next unless (m & WLOCK) == UNLOCKED

        m, success = @m.compare_and_set(m, m | WLOCK, :acquire, :relaxed)
        next unless success

        return if (m & RMASK) == UNLOCKED
        break
      end

      backoff_loop do
        m = @m.get(:relaxed)
        break if (m & RMASK) == UNLOCKED
      end
    end

    @[AlwaysInline]
    def write_unlock : Nil
      @m.set(UNLOCKED, :release)
    end

    @[AlwaysInline]
    def read_lock : Nil
      _, success = @m.compare_and_set(UNLOCKED, RLOCK, :acquire, :relaxed)
      read_lock_slow unless success
    end

    @[NoInline]
    private def read_lock_slow : Nil
      backoff_loop do
        m = @m.get(:relaxed)
        next unless (m & WLOCK) == UNLOCKED

        _, success = @m.compare_and_set(m, m + RLOCK, :acquire, :relaxed)
        break if success
      end
    end

    @[AlwaysInline]
    def read_unlock : Nil
      @m.sub(RLOCK, :release)
    end

    private def backoff_loop(&)
      attempts = 0
      while true
        yield
        attempts = Thread.delay(attempts)
      end
    end
  end

  # :nodoc:
  #
  # Pool of global spinning rwlocks to protect the value of any pointer.
  #
  # The same rwlock can be used for different pointers at the same time, though
  # the protected sections are small (get/set global value) and there should be
  # enough rwlocks to avoid contention.
  struct RWLockBuckets
    # enough space for rwlock + padding to avoid false sharing
    PADDED_RWLOCK_BYTESIZE = {{ flag?(:bits64) ? 64 : 32 }}

    @buffer : UInt8*
    @mask : UInt64

    def initialize
      count = Math.pw2ceil(System.cpu_count * 4)
      @buffer = GC.malloc(PADDED_RWLOCK_BYTESIZE * count).as(UInt8*)
      @mask = (count &- 1).to_u64!
    end

    @[AlwaysInline]
    def probe(key : Pointer) : RWLock*
      ptr = @buffer + (hash(key) & @mask).to_i64!
      ptr.as(RWLock*)
    end

    # hash method copied from the parking_lot_core Rust crate (MIT, Apache 2.0)
    # https://github.com/Amanieu/parking_lot/blob/a0a380cfe417ae04ea804817e71205ccaf92a781/core/src/parking_lot.rs#L343-L353
    private def hash(key) : UInt64
      {% if flag?(:bits64) %}
        key.address &* 0x9E3779B97F4A7C15_u64
      {% else %}
        key.address &* 0x000000009E3779B9_u64
      {% end %}
    end
  end

  # :nodoc:
  RWLOCKS = RWLockBuckets.new
end

# :nodoc:
@[AlwaysInline]
fun __crystal_rwlock(addr : Void*) : Void*
  Crystal::RWLOCKS.probe(addr).as(Void*)
end

# :nodoc:
@[AlwaysInline]
fun __crystal_lock(rwlock : Void*) : Nil
  rwlock.as(Crystal::RWLock*).value.write_lock
end

# :nodoc:
@[AlwaysInline]
fun __crystal_unlock(rwlock : Void*) : Nil
  rwlock.as(Crystal::RWLock*).value.write_unlock
end

# :nodoc:
@[AlwaysInline]
fun __crystal_rlock(rwlock : Void*) : Nil
  rwlock.as(Crystal::RWLock*).value.read_lock
end

# :nodoc:
@[AlwaysInline]
fun __crystal_runlock(rwlock : Void*) : Nil
  rwlock.as(Crystal::RWLock*).value.read_unlock
end
