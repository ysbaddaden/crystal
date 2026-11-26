lib LibC
  fun abort : NoReturn
end

# These hooks let codegen emit exception handlers for examples that never unwind.
fun __crystal_personality(version : Int32, actions : Int32, exception_class : UInt64, exception : Void*, context : Void*) : Int32
  LibC.abort
end

fun __crystal_get_exception(exception : Void*) : UInt64
  LibC.abort
end

fun __crystal_raise(exception : Void*) : NoReturn
  LibC.abort
end
