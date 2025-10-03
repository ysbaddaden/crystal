require "c/synchapi"

class Thread
  def self.wait(address : UInt32*, value : UInt32, timeout : Time::Span? = nil) : Bool
    timeout_ms = timeout.try(&.total_milliseconds.to_i.clamp(1..)) || LibC::INFINITE

    ret = LibC.WaitOnAddress(address, pointerof(value), sizeof(UInt32), timeout_ms)
    return false if ret == 1

    case win_error = WinError.value
    when WinError::ERROR_TIMEOUT
      true
    else
      raise RuntimeError.from_os_error("Thread.wait", win_error)
    end
  end

  def self.wake_one(address : UInt32*) : Nil
    LibC.WakeByAddressSingle(address)
  end

  def self.wake_all(address : UInt32*) : Nil
    LibC.WakeByAddressAll(address)
  end
end
