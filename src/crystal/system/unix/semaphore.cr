{% skip_file unless flag?(:unix) && !flag?(:darwin) %}

require "c/semaphore"

struct Crystal::System::Semaphore
  @sem = uninitialized LibC::SemT

  def initialize(value : Int)
    if LibC.sem_init(pointerof(@sem), 0, value.to_u32) == -1
      raise RuntimeError.from_errno("sem_init")
    end
  end

  def wait(timeout : Nil) : Nil
    while true
      ret = LibC.sem_wait(pointerof(@sem))
      return unless ret == -1
      raise RuntimeError.from_errno("sem_wait") unless Errno.value == Errno::EINTR
    end
  end

  def wait(timeout : Time::Span) : Bool
    deadline = now + timeout

    ts = uninitialized Timespec
    ts.tv_sec = typeof(ts.tv_sec).new(deadline.@seconds)
    ts.tv_nsec = typeof(ts.tv_nsec).new(deadline.@nanoseconds)

    while true
      ret = LibC.sem_timedwait(pointerof(@sem), pointerof(ts))
      return false unless ret == -1

      case Errno.value
      when Errno::EINTR
        # retry
      when Errno::ETIMEDOUT
        return true if deadline < now
      else
        raise RuntimeError.from_errno("sem_timedwait")
      end
    end
  end

  private def now : Time::Span
    if LibC.clock_gettime(LibC::CLOCK_REALTIME, out ts) == -1
      raise RuntimeError.from_errno("clock_gettime")
    end
    Time::Span.new(seconds: ts.tv_sec, nanoseconds: ts.tv_nsec)
  end

  def wake : Nil
    if LibC.sem_post(pointerof(@sem)) == -1
      raise RuntimeError.from_errno("sem_post")
    end
  end

  def destroy : Nil
    if LibC.sem_destroy(pointerof(@sem)) == -1
      raise RuntimeError.from_errno("sem_destroy")
    end
  end
end
