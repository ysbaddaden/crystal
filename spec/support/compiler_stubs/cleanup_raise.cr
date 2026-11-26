lib LibC
  fun abort : NoReturn
end

# Lets semantic cleanup replace untyped expressions with a NoReturn call.
def raise(message : String) : NoReturn
  LibC.abort
end
