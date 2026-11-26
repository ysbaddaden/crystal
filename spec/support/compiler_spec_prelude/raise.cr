require "./lib_c"
require "./string"
require "./pointer"
require "./enum"
require "crystal/system/exceptions"

module Crystal::System
  def self.panic!(message, *args)
    LibC.printf(message, *args)
    LibC.exit(33)
  end
end

class Exception
  def initialize(@message : String? = nil)
  end

  def message : String?
    @message
  end
end

class TypeCastError < Exception
end

class IndexError < Exception
end

class NilAssertionError < Exception
  def initialize(message = "Nil assertion failed")
    super(message)
  end
end

def raise(message : String) : NoReturn
  raise Exception.new(message)
end

def raise(exception : Exception) : NoReturn
  raise_without_backtrace(exception)
end

fun __crystal_raise_overflow
  raise Exception.new("math overflow")
end

fun __crystal_raise_closure_to_c : NoReturn
  raise "passing a closure to C is not allowed"
end

fun __crystal_raise_cast_failed(from_type : Void*, to_type : Void*, location : Void*) : NoReturn
  hsize = offsetof(String, @c)
  ptr = Pointer(UInt8).malloc(256_u64 + hsize)
  size =
    if location
      LibC.snprintf(ptr + hsize, 256, "Cast from %s to %s failed, at %s", from_type.as(String), to_type.as(String), location.as(String))
    else
      LibC.snprintf(ptr + hsize, 256, "Cast from %s to %s failed", from_type.as(String), to_type.as(String))
    end
  raise TypeCastError.new(size > 0 ? String.new(ptr, size) : "cast failed (no message)")
end
