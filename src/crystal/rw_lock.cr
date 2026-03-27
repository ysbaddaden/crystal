# :nodoc:
struct Crystal::RWLock
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
    rlock_slow unless success
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
