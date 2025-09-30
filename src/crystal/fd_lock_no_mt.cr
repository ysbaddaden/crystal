# :nodoc:
#
# Simplee, but thread unsafe, alternative to Crystal::FdLock that only locks for
# read and write and otherwise doesn't count references or waits for references
# before closing. This is mostly needed for the interpreter that happens to
# segfault with the thread safe alternative (src/crystal/fd_lock_mt.cr)
struct Crystal::FdLock
  CLOSED = 1_u8 << 0
  RLOCK  = 1_u8 << 1
  WLOCK  = 1_u8 << 2

  @m = 0_u8
  @readers = PointerLinkedList(Fiber::PointerLinkedListNode).new
  @writers = PointerLinkedList(Fiber::PointerLinkedListNode).new

  def read(&)
    synchronize(RLOCK, pointerof(@readers)) { yield }
  end

  def write(&)
    synchronize(WLOCK, pointerof(@writers)) { yield }
  end

  private def synchronize(xlock, waiters, &)
    while true
      if closed?
        raise IO::Error.new("Closed")
      elsif (@m & xlock) == 0_u8
        @m |= xlock
        break
      else
        waiter = Fiber::PointerLinkedListNode.new(Fiber.current)
        waiters.value.push(pointerof(waiter))
        Fiber.suspend
      end
    end

    begin
      yield
    ensure
      @m &= ~xlock

      if w = waiters.value.shift?
        w.value.enqueue
      end
    end
  end

  def reference(&)
    raise IO::Error.new("Closed") if closed?
    yield
  end

  def reset : Nil
    @m = 0_u8
  end

  def closed?
    (@m & CLOSED) == CLOSED
  end

  def try_close?(&)
    if closed?
      false
    else
      @m |= CLOSED

      @readers.consume_each(&.value.enqueue)
      @writers.consume_each(&.value.enqueue)

      yield
      true
    end
  end
end
