class Exception
end

class RuntimeError < Exception
end

lib LibC
  @[Raises]
  fun abort : NoReturn
end

# Only used to type the control flow around exception handlers.
def raise(error : Exception) : NoReturn
  LibC.abort
end

def raise(message : String) : NoReturn
  raise RuntimeError.new
end
