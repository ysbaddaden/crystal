{% skip_file unless flag?(:darwin) %}

require "c/os/clock"
require "c/os/os_sync_wait_on_address"

class Thread
  def self.wait(address : UInt32*, value : UInt32, timeout : Time::Span? = nil) : Bool
    ret =
      {% if LibC.has_method?(:os_sync_wait_on_address) %}
        if timeout
          timeout_ns = timeout.total_nanoseconds.to_i.clamp(0..)
          LibC.os_sync_wait_on_address_with_timeout(address, value, sizeof(UInt32), LibC::OS_SYNC_WAIT_ON_ADDRESS_NONE, LibC::OS_CLOCK_MACH_ABSOLUTE_TIME, timeout_ns)
        else
          LibC.os_sync_wait_on_address(address, value, sizeof(UInt32), LibC::OS_SYNC_WAIT_ON_ADDRESS_NONE)
        end
      {% elsif LibC.has_method?(:__ulock_wait2) %}
        timeout_ns = timeout.try(&.total_nanoseconds.to_i.clamp(0..)) || 0
        LibC.__ulock_wait2(LibC::UL_COMPARE_AND_WAIT, address, value, timeout_ns, 0)
      {% else %}
        timeout_us = timeout.try(&.total_microseconds.to_i.clamp(1..)) || 0
        LibC.__ulock_wait(LibC::UL_COMPARE_AND_WAIT, address, value, timeout_us)
      {% end %}
    return false unless ret == -1

    case Errno.value
    when Errno::EFAULT, Errno::EINTR
      false
    when Errno::ETIMEDOUT
      true
    else
      raise RuntimeError.new("Thread.wait")
    end
  end

  def self.wake_one(address : UInt32*) : Nil
    ret =
      {% if LibC.has_method?(:os_sync_wait_on_address) %}
        LibC.os_sync_wake_by_address_any(address, sizeof(UInt32), LibC::OS_SYNC_WAKE_BY_ADDRESS_NONE)
      {% else %}
        LibC.__ulock_wake(LibC::UL_COMPARE_AND_WAIT, address, sizeof(UInt32))
      {% end %}

    raise RuntimeError.new("Thread.wake_one") if ret == -1
  end

  def self.wake_all(address : UInt32*) : Nil
    ret =
      {% if LibC.has_method?(:os_sync_wait_on_address) %}
        LibC.os_sync_wake_by_address_all(address, sizeof(UInt32), LibC::OS_SYNC_WAKE_BY_ADDRESS_NONE)
      {% else %}
        LibC.__ulock_wake(LibC::UL_COMPARE_AND_WAIT | LibC::ULF_WAKE_ALL, address, sizeof(UInt32))
      {% end %}

    raise RuntimeError.new("Thread.wake_all") if ret == -1
  end
end
