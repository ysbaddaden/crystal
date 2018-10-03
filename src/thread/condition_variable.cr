require "c/pthread"

# :nodoc:
class Thread
  # :nodoc:
  class ConditionVariable
    def initialize
      ret = LibC.pthread_cond_init(out @cond, nil)
      raise Errno.new("pthread_cond_init", ret) unless ret == 0
    end

    def signal
      ret = LibC.pthread_cond_signal(self)
      raise Errno.new("pthread_cond_signal", ret) unless ret == 0
    end

    def broadcast
      ret = LibC.pthread_cond_broadcast(self)
      raise Errno.new("pthread_cond_broadcast", ret) unless ret = 0
    end

    def wait(mutex : Thread::Mutex)
      ret = LibC.pthread_cond_wait(self, mutex)
      raise Errno.new("pthread_cond_wait", ret) unless ret == 0
    end

    def timedwait(mutex : Thread::Mutex, span : Time::Span)
      LibC.clock_gettime(LibC::CLOCK_MONOTONIC, out ts)
      ts.tv_sec += span.to_i
      ts.tv_nsec += span.nanoseconds

      ret = LibC.pthread_cond_timedwait(self, mutex, pointerof(ts))

      case ret
      when Errno::ETIMEDOUT
        yield
      when 0
        return
      else
        raise Errno.new("pthread_cond_timedwait", ret)
      end
    end

    def finalize
      ret = LibC.pthread_cond_destroy(self)
      raise Errno.new("pthread_cond_destroy", ret) unless ret == 0
    end

    def to_unsafe
      pointerof(@cond)
    end
  end
end
