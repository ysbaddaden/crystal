# Stores the actual elements of nonempty array literals in codegen specs.
class Array(T)
  def self.unsafe_build(size : Int32)
    new(size)
  end

  def initialize(@size : Int32)
    @buffer = Pointer(T).malloc(@size.to_u64!)
  end

  def size
    @size
  end

  def [](index : Int32) : T
    (@buffer + index.to_i64!).value
  end

  def each(&) : Nil
    index = 0
    while index < @size
      yield self[index]
      index = index &+ 1
    end
  end

  def sum
    total = 0
    each { |element| total += element }
    total
  end

  def to_unsafe
    @buffer
  end
end

struct Pointer(T)
  def []=(index : Int32, value : T) : T
    (self + index.to_i64!).value = value
  end
end
