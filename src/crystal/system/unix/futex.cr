{% if flag?(:freebsd) %}
  require "c/sys/umtx"
{% elsif flag?(:linux) %}
  require "c/linux/futex"
  require "./syscall"
{% elsif flag?(:openbsd) %}
  require "c/sys/futex"
{% else %}
  {% skip_file %}
{% end %}

class Thread
  def self.wait(address : UInt32*, value : UInt32, timeout : Time::Span? = nil) : Bool
    if timeout
      ts = uninitialized LibC::Timespec
      ts.tv_sec = typeof(ts.tv_sec).new(timeout.@seconds)
      ts.tv_nsec = typeof(ts.tv_nsec).new(timeout.@nanoseconds)
      timespec = pointerof(ts)
    else
      timespec = Pointer(LibC::Timespec).null
    end

    ret =
      {% if flag?(:freebsd) %}
        ts_size = Pointer(Void).new(timeout ? sizeof(LibC::Timespec) : 0)
        LibC._umtx_op(address, LibC::UMTX_OP_WAIT_UINT_PRIVATE, value, ts_size, timespec)
      {% elsif flag?(:linux) %}
        linux_futex(address, LibC::FUTEX_WAIT_PRIVATE, value, timespec)
      {% elsif flag?(:openbsd) %}
        LibC.futex(address, LibC::FUTEX_WAIT, value, timespec, nil)
      {% end %}
    return false unless ret == -1

    case Errno.value
    when Errno::EAGAIN, Errno::EINTR
      false
    when Errno::ETIMEDOUT
      true
    else
      raise RuntimeError.from_errno("Thread.wait")
    end
  end

  def self.wake_one(address : UInt32*) : Nil
    wake_impl(address, 1_u32) { "Thread.wake_one" }
  end

  def self.wake_all(address : UInt32*) : Nil
    wake_impl(address, Int32::MAX) { "Thread.wake_all" }
  end

  private def self.wake_impl(address, count, &)
    ret =
      {% if flag?(:freebsd) %}
        LibC._umtx_op(address, LibC::UMTX_OP_WAKE_PRIVATE, count, nil, nil)
      {% elsif flag?(:linux) %}
        linux_futex(address, LibC::FUTEX_WAKE_PRIVATE, count.to_u32, Pointer(LibC::Timespec).null)
      {% elsif flag?(:openbsd) %}
        LibC.futex(address, LibC::FUTEX_WAKE, count, nil, nil)
      {% end %}

    raise RuntimeError.from_errno(yield) if ret == -1
  end

  {% if flag?(:linux) %}
    def self.linux_futex(address, op, value, timespec)
      ret = Crystal::System::Syscall.futex(address, op, value, timespec, Pointer(UInt32).null, 0_u32).to_i32!
      if ret < 0
        Errno.value = Errno.new(-ret)
        -1
      else
        ret
      end
    end
  {% end %}
end
