# Provides real storage for codegen specs with a single array element.
class Array(T)
  def self.unsafe_build(size : Int32)
    LibC.abort unless size == 1
    new
  end

  def initialize
    @value = uninitialized T
  end

  def to_unsafe
    pointerof(@value)
  end

  def <<(value : T) : self
    @value = value
    self
  end

  def [](index : Int32) : T
    LibC.abort unless index == 0
    @value
  end
end

struct Pointer(T)
  def []=(index : Int32, value : T) : T
    LibC.abort unless index == 0
    self.value = value
  end
end

lib LibC
  fun abort : NoReturn
end
