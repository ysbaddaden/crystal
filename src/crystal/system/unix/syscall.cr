{% skip_file unless flag?(:linux) && !flag?(:interpreted) %}

require "c/unistd"
require "syscall"

module Crystal::System::Syscall
  GRND_NONBLOCK = 1u32

  ::Syscall.def_syscall futex, LibC::Long, uaddr : LibC::UInt*, futex_op : LibC::Int, val : UInt32, timeout : LibC::Timespec*, uaddr2 : UInt32*, val3 : UInt32
  ::Syscall.def_syscall getrandom, LibC::SSizeT, buf : UInt8*, buflen : LibC::SizeT, flags : UInt32
  ::Syscall.def_syscall sched_getaffinity, LibC::Int, pid : LibC::PidT, cpusetsize : LibC::SizeT, mask : Pointer(UInt8)
end
