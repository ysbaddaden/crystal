require "./types"
require "../signal"

lib LibC
  WNOHANG = 1

  fun waitpid(pid : PidT, status : Int*, options : Int) : PidT
end
