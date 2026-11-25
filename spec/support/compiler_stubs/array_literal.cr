# Supports array-literal lowering in semantic-only inputs.
class Array(T)
  def self.unsafe_build(size : Int32)
    new(size)
  end

  def initialize(@size : Int32)
  end

  def size
    @size
  end

  def to_unsafe
    Pointer(T).new(0)
  end
end

struct Pointer(T)
  def []=(index : Int32, value : T)
  end
end
