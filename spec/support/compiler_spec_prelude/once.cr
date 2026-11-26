# Implements once initialization for linked specs that run on a single thread.
fun __crystal_once(flag : Bool*, initializer : Void*)
  return if flag.value
  callback = {initializer, Pointer(Void).new(0)}
  pointerof(callback).as(Proc(Nil)*).value.call
  flag.value = true
end
