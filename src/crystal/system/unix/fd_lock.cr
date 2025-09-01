require "crystal/parking_lot"

# :nodoc:
#
# Tracks active references over a system file descriptor (fd).
#
# Every read on the fd must lock read, every write must lock write and every
# other operation (fcntl, setsockopt, ...) must take a shared lock (increment
# references). There can at most one reader + one writer + many references
# (other operations) at the same time.
#
# The fd can be closed at any time, but the actual system close will be delayed
# until there are no more references left. This avoids potential races when a
# thread might try to read a fd that has been closed and has been reused by the
# OS.
#
# It also guarantees that there's only one attempt to read (or write) at a
# time, which avoids situations where 2 readers are waiting, then the first
# reader is resumed but doesn't consume everything, then the second reader will
# never be resumed. With this lock a waiting reader will always be resumed.
struct Crystal::System::FdLock
  CLOSED  = 1_u32      # the lock is closed: can't rlock/wlock/incref anymore
  CLOSING = 1_u32 << 1 # the closing fiber is waiting (must be woken once)
  RLOCK   = 1_u32 << 2 # the reader lock bit
  RWAIT   = 1_u32 << 3 # one or more readers are waiting to lock (must be woken)
  WLOCK   = 1_u32 << 4 # the writer lock bit
  WWAIT   = 1_u32 << 5 # one or more writers are waiting to lock (must be woken)
  REF     = 1_u32 << 6 # the reference counter increment
  MASK    = ~(REF - 1) # the reference counter

  @m = Atomic(UInt32).new(0_u32)

  # the pointers below are just keys for the parking lot, they will never be
  # dereferenced, and just need to be unique for each queue, and conveniently
  # use pointers to the state word

  private def closing : Void*
    pointerof(@m).as(Void*)
  end

  private def readers : Void*
    pointerof(@m).as(Void*) + 1
  end

  private def writers : Void*
    pointerof(@m).as(Void*) + 2
  end

  # Increments the references by one for the duration of the block.
  #
  # Raises if the fdlock is closed.
  def reference(& : -> F) : F forall F
    increment_ref
    begin
      yield
    ensure
      decrement_ref
    end
  end

  # Locks for read and increments the references by one for the duration of the
  # block. Unlocks read before returning.
  #
  # Raises if the fdlock is closed.
  def read(& : -> F) : F forall F
    increment_ref(RLOCK, RWAIT, readers)
    begin
      yield
    ensure
      decrement_ref(RLOCK, RWAIT, readers)
    end
  end

  # Locks for write and increments the references by one for the duration of the
  # block. Unlocks write before returning.
  #
  # Raises if the fdlock is closed.
  def write(& : -> F) : F forall F
    increment_ref(WLOCK, WWAIT, writers)
    begin
      yield
    ensure
      decrement_ref(WLOCK, WWAIT, writers)
    end
  end

  # Closes the fdlock (not the fd). Wakes all waiting readers/writers. Blocks
  # until all references are terminated before returning.
  def close(& : ->) : Nil
    unless increment_ref_and_close?
      return
    end

    begin
      yield
    ensure
      m = @m.get(:relaxed)
      loop do
        m, success = @m.compare_and_set(m, m | CLOSING, :relaxed, :relaxed)
        break if success
      end

      decrement_ref_slow(closing_fiber: true)
    end

    # wait for active references to complete;
    # we must abort if the CLOSING bit has been removed
    return unless (@m.get(:relaxed) & CLOSING) == CLOSING

    ParkingLot.wait(closing) do
      (@m.get(:relaxed) & CLOSING) == CLOSING
    end
  end

  @[AlwaysInline]
  private def increment_ref(lock = 0_u32, wait = 0_u32, waiters = Pointer(UInt8).null)
    # fast-path: uncontented
    _, success = @m.compare_and_set(UNLOCKED, lock &+ REF, :acquire, :relaxed)
    return if success

    # slow-path: may have to spin or wait
    if waiters
      increment_ref_slow(lock, wait, waiters)
    else
      increment_ref_slow
    end
  end

  @[AlwaysInline]
  private def decrement_ref(lock = 0_u32, wait = 0_u32, waiters = Pointer(UInt8).null)
    # fast-path: uncontented; always fails when closed, so the last ref must
    # wake the closing fiber
    _, success = @m.compare_and_set(lock &+ REF, UNLOCKED, :release, :relaxed)
    return if success

    # slow-path: may have to spin or wait
    if waiters
      decrement_ref_slow(lock, wait, waiters)
    else
      decrement_ref_slow
    end
  end

  @[NoInline]
  private def increment_ref_and_close? : Bool
    attempts = 0

    loop do
      m = @m.get(:relaxed)

      if (m & CLOSED) == CLOSED
        # already closed: abort
        return false
      end

      # try to close + incr refs
      new_m = (m | CLOSED) &+ REF
      raise IO::Error.new("Too many concurrent operations") if (new_m & MASK) == 0

      m, success = @m.compare_and_set(m, new_m, :acquire, :relaxed)
      if success
        # wake all waiters (if any)
        ParkingLot.wake(readers) { } if (m & RWAIT) == RWAIT
        ParkingLot.wake(writers) { } if (m & WWAIT) == WWAIT
        return true
      end

      attempts = Thread.delay(attempts)
    end
  end

  @[NoInline]
  private def increment_ref_slow : Nil
    attempts = 0

    loop do
      m = @m.get(:relaxed)

      if (m & CLOSED) == CLOSED
        raise IO::Error.new("Closed")
      end

      # try to incr refs
      new_m = m &+ REF
      raise IO::Error.new("Too many concurrent operations") if (new_m & MASK) == 0

      _, success = @m.compare_and_set(m, new_m, :acquire, :relaxed)
      return if success

      attempts = Thread.delay(attempts)
    end
  end

  @[NoInline]
  private def increment_ref_slow(lock, wait, waiters) : Nil
    attempts = 0

    loop do
      m = @m.get(:relaxed)

      if (m & CLOSED) == CLOSED
        raise IO::Error.new("Closed")
      end

      if (m & lock) == 0_u32
        # unlocked: try to acquire + incr refs
        new_m = (m | lock) &+ REF
        raise IO::Error.new("Too many concurrent operations") if (new_m & MASK) == 0
        _, success = @m.compare_and_set(m, new_m, :acquire, :relaxed)
        return if success

        attempts = Thread.delay(attempts)
      else
        # wait until the lock is released
        _, success = @m.compare_and_set(m, m | wait, :relaxed, :relaxed)
        next unless success

        ParkingLot.wait(waiters) do
          # wait if !closed and both the lock & wait bits are still set
          (@m.get(:relaxed) & (CLOSED | lock | wait)) == (lock | wait)
        end

        attempts = 0
      end
    end
  end

  @[NoInline]
  private def decrement_ref_slow(closing_fiber = false) : Nil
    close_if_last_ref(@m.sub(REF, :release), closing_fiber)
  end

  @[NoInline]
  private def decrement_ref_slow(lock, wait, waiters) : Nil
    ParkingLot.wake(waiters, count: 1) do |has_waiting_fibers|
      clear = lock
      clear |= wait unless has_waiting_fibers

      attempts = 0

      m = @m.get(:relaxed)
      loop do
        m, success = @m.compare_and_set(m, (m & ~clear) &- REF, :release, :relaxed)
        break if success

        attempts = Thread.delay(attempts)
      end

      close_if_last_ref(m)
    end
  end

  # The last reference after close must resume the closing fiber.
  private def close_if_last_ref(m, closing_fiber)
    return unless (m & (CLOSED | MASK)) == (CLOSED | REF)

    if closing_fiber
      # the calling fiber is the closing fiber and hasn't suspended (yet), clear
      # the CLOSING bit to tell #close to not suspend; there's no need for a
      # CAS: we can't lock, unlock or incref anymore and there are no more
      # references that must decref
      @m.set(CLOSED, :relaxed)
    else
      ParkingLot.wake(closing) { }
    end
  end
end
