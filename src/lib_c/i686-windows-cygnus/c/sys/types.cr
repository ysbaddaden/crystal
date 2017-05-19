require "../stddef"
require "../stdint"

lib LibC
  # alias BlkcntT = Long
  alias BlksizeT = Int
  alias ClockT = ULong
  alias ClockidT = ULong
  alias DevT = UInt
  alias GidT = UInt
  alias IdT = UInt
  # alias InoT = ULong
  alias ModeT = UInt
  alias NlinkT = UShort
  # alias OffT = Long
  alias PidT = Int
  type PthreadAttrT = Void*
  type PthreadCondT = Void*
  type PthreadCondattrT = Void*
  type PthreadMutexT = Void*
  type PthreadMutexattrT = Void*
  type PthreadT = Void*
  alias SSizeT = Long
  alias SusecondsT = Long
  alias TimeT = Long
  alias UidT = UInt

  # LARGE FILE (64 bits)
  alias BlkcntT = LongLong
  alias InoT = ULongLong
  alias OffT = LongLong
end
