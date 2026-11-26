require "./lib_c"

class Exception
end

class NilAssertionError < Exception
  def initialize(message : String)
  end
end

class IndexError < Exception
  def initialize(message : String = "Index out of bounds")
  end
end

# Only used to type the control flow around exception handlers.
def raise(error : Exception) : NoReturn
  LibC.abort
end

# Cleanup can emit this call after semantic analysis has finished.
def raise(message : String) : NoReturn
  LibC.abort
end

fun __crystal_raise_cast_failed(from_type : Void*, to_type : Void*, location : Void*) : NoReturn
  LibC.abort
end

fun __crystal_raise_overflow : NoReturn
  LibC.abort
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
