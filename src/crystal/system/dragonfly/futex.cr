{% skip_file unless flag?(:dragonfly) %}

require "c/unistd"

class Thread
  def self.wait(address : UInt32*, value : UInt32, timeout : Time::Span? = nil) : Bool
    timeout_us = timeout.try(&.total_microseconds.to_i.clamp(1..)) || 0

    ret = LibC.umtx_sleep(address, value, timeout_us) == -1
    return false unless ret == -1

    case Errno.value
    when Errno::EBUSY, Errno::EINTR
      false
    when Errno::EWOULDBLOCK
      true
    else
      raise RuntimeError.from_os_error("Thread.wait")
    end
  end

  def self.wake_one(address : UInt32*) : Nil
    wake_impl(address, 1) { "Thread.wake_one" }
  end

  def self.wake_all(address : UInt32*) : Nil
    wake_impl(address, Int32::MAX) { "Thread.wake_all" }
  end

  private def self.wake_impl(address, count, &)
    if LibC.umtx_wakeup(address, count) == -1
      raise RuntimeError.new(yield)
    end
  end
end
