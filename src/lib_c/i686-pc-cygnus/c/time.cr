require "./sys/types"

lib LibC
  CLOCK_MONOTONIC = ClockidT.new(4)
  CLOCK_REALTIME  = ClockidT.new(1)

  struct Tm
    tm_sec : Int
    tm_min : Int
    tm_hour : Int
    tm_mday : Int
    tm_mon : Int
    tm_year : Int
    tm_wday : Int
    tm_yday : Int
    tm_isdst : Int
    tm_gmtoff : Long
    tm_zone : Char*
  end

  struct Timespec
    tv_sec : TimeT
    tv_nsec : Long
  end

  fun clock_gettime(clock_id : ClockidT, tp : Timespec*) : Int
  fun clock_settime(clock_id : ClockidT, tp : Timespec*) : Int
  fun gmtime_r(x0 : TimeT*, x1 : Tm*) : Tm*
  fun localtime_r(x0 : TimeT*, x1 : Tm*) : Tm*
  fun mktime(timeptr : Tm*) : TimeT
  fun tzset : Void
  fun timegm(x0 : Tm*) : TimeT

  $daylight : Int
  $timezone : Long
  $tzname : StaticArray(Char*, 2)
end
