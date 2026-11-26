require "./pointer"

struct Proc
  def closure? : Bool
    func = self
    !pointerof(func).as({Void*, Void*}*).value[1].null?
  end
end
