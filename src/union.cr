# A union type represents the possibility of a variable or an expression
# having more than one possible type at compile time.
#
# When invoking a method on a union type, the language checks that the
# method exists and can be resolved (typed) for each type in the union.
# For this reason, adding instance methods to `Union` makes no sense and
# has no effect. However, adding class method to `Union` is possible
# and can be useful. One example is parsing `JSON` into one of many
# possible types.
#
# Union is special in that it is a generic type but instantiating it
# might not return a union type:
#
# ```
# Union(Int32 | String)      # => (Int32 | String)
# Union(Int32)               # => Int32
# Union(Int32, Int32, Int32) # => Int32
# ```
struct Union
end

# TODO: merge below implementation with Crystal::RWLock (spin lock)

private UNLOCKED = 0_u32
private WLOCK    = 1_u32
private RLOCK    = 2_u32
private RMASK    = ~(RLOCK - 1)

# :nodoc:
@[AlwaysInline]
fun __crystal_rlock(word : UInt32*) : Nil
  _, success = Atomic::Ops.cmpxchg(word, UNLOCKED, RLOCK, :acquire, :monotonic)
  __crystal_rlock_slow(word) unless success
end

# :nodoc:
@[NoInline]
def __crystal_rlock_slow(word) : Nil
  attempts = 0

  while true
    value = Atomic::Ops.load(word, :monotonic, volatile: true)
    if (value & WLOCK) == 0_u32
      _, success = Atomic::Ops.cmpxchg(word, value, value + RLOCK, :acquire, :monotonic)
      return if success
    end
    attempts = Thread.delay(attempts)
  end
end

# :nodoc:
@[AlwaysInline]
fun __crystal_runlock(word : UInt32*) : Nil
  Atomic::Ops.atomicrmw(:sub, word, RLOCK, :release, singlethread: false)
end

# :nodoc:
@[AlwaysInline]
fun __crystal_lock(word : UInt32*) : Nil
  _, success = Atomic::Ops.cmpxchg(word, UNLOCKED, WLOCK, :acquire, :monotonic)
  __crystal_lock_slow(word) unless success
end

# :nodoc:
@[NoInline]
def __crystal_lock_slow(word : UInt32*) : Nil
  attempts = 0

  # lock write (prevents parallel lock/rlock)
  while true
    value = Atomic::Ops.load(word, :monotonic, volatile: true)
    if (value & WLOCK) == 0_u32
      _, success = Atomic::Ops.cmpxchg(word, value, WLOCK, :acquire, :monotonic)
      break if success
    end
    attempts = Thread.delay(attempts)
  end

  attempts = 0

  # wait for readers to be unlock
  until (value & RMASK) == 0_u32
    attempts = Thread.delay(attempts)
    value = Atomic::Ops.load(word, :monotonic, volatile: true)
  end
end

# :nodoc:
@[AlwaysInline]
fun __crystal_unlock(word : UInt32*) : Nil
  Atomic::Ops.store(word, UNLOCKED, :release, volatile: true)
end
