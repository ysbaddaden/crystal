require "c/sys/time"

lib LibC
  FUTEX_WAIT = 1
  FUTEX_WAKE = 2

  fun futex(UInt32*, Int, Int, Timespec*, UInt32*) : Int
end
