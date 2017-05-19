require "./types"
require "./time"
require "../time"
require "../signal"

lib LibC
  alias FdMask = ULong

  struct FdSet
    fds_bits : StaticArray(FdMask, 1)
  end

  fun select(n : Int, readfds : Void*, writefds : Void*, exceptfds : Void*, timeout : Timeval*) : Int
end
