lib LibC
  alias SemT = Void*

  fun sem_init(SemT*, Int, UInt) : Int
  fun sem_wait(SemT*) : Int
  fun sem_timedwait(SemT*, Timespec*) : Int
  fun sem_destroy(SemT*) : Int
end
