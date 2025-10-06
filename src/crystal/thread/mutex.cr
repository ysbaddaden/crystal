require "./mu"

class Thread
  class Mutex
    @mu = MU.new
    @locked_by : Crystal::System::Thread::Handle | Nil

    def synchronize(&)
      lock
      begin
        yield
      ensure
        unlock
      end
    end

    def lock : Nil
      unless @mu.try_lock?
        raise RuntimeError.new("Deadlock") if owns_lock?
        @mu.lock_slow
      end
      @locked_by = Crystal::System::Thread.current_handle
    end

    def try_lock : Bool
      if locked = @mu.try_lock?
        @locked_by = Crystal::System::Thread.current_handle
      end
      locked
    end

    def unlock : Nil
      owns_lock!
      @locked_by = nil
      @mu.unlock
    end

    protected def wait(&)
      owns_lock!
      @locked_by = nil
      result = yield pointerof(@mu)
      @locked_by = Crystal::System::Thread.current_handle
      result
    end

    private def owns_lock!
      unless @mu.held?
        raise RuntimeError.new("Can't unlock Thread::Mutex that isn't locked")
      end
      unless owns_lock?
        raise RuntimeError.new("Can't unlock Thread::Mutex locked by another thread")
      end
    end

    private def owns_lock?
      # we should use pthread_equal on POSIX but all the targets alias pthread_t
      # as an integer or pointer type that we can directly compare (and their
      # pthread_equal is doing a mere a == b comparison)
      @locked_by == Crystal::System::Thread.current_handle
    end
  end
end
