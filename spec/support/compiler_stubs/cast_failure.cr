lib LibC
  fun abort : NoReturn
end

fun __crystal_raise_cast_failed(from_type : Void*, to_type : Void*, location : Void*) : NoReturn
  LibC.abort
end
