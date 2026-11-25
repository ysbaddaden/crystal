lib LibC
  fun abort : NoReturn
end

fun __crystal_raise_overflow : NoReturn
  LibC.abort
end
