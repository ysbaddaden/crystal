require "./types"

lib LibC
  PROT_EXEC             =    4
  PROT_NONE             =    0
  PROT_READ             =    1
  PROT_WRITE            =    2
  MAP_FIXED             = 0x10
  MAP_PRIVATE           =    2
  MAP_SHARED            =    1
  MAP_ANON              = LibC::MAP_ANONYMOUS
  MAP_ANONYMOUS         = 0x20
  MAP_FAILED            = Pointer(Void).new(-1)
  POSIX_MADV_DONTNEED   = 4
  POSIX_MADV_NORMAL     = 0
  POSIX_MADV_RANDOM     = 2
  POSIX_MADV_SEQUENTIAL = 1
  POSIX_MADV_WILLNEED   = 3
  MADV_DONTNEED         = 4
  MADV_NORMAL           = 0
  MADV_RANDOM           = 2
  MADV_SEQUENTIAL       = 1
  MADV_WILLNEED         = 3

  fun mmap(addr : Void*, len : SizeT, prot : Int, flags : Int, fd : Int, off : OffT) : Void*
  fun mprotect(addr : Void*, len : SizeT, prot : Int) : Int
  fun munmap(addr : Void*, len : SizeT) : Int
  fun madvise(addr : Void*, len : SizeT, advice : Int) : Int
end
