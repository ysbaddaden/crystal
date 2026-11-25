require "proc"

struct Pointer(T)
  def null? : Bool
    address == 0
  end
end
