require "primitives"
require "./enumerable"
require "./indexable"
require "./lib_c"
require "./pointer"

# Minimal storage for literals and the collection operations used by compiler specs.
class Array(T)
  include Enumerable(T)
  include Indexable(T)

  def self.unsafe_build(size : Int32)
    new(size)
  end

  def initialize(@size : Int32 = 0)
    @buffer = Pointer(T).malloc(@size.to_u64!)
  end

  def size
    @size
  end

  def [](index : Int) : T
    LibC.abort unless 0 <= index < @size
    (@buffer + index.to_i64!).value
  end

  def last : T
    self[@size &- 1]
  end

  def push(value : T) : self
    @buffer = @buffer.realloc((@size &+ 1).to_u64!)
    @buffer[@size] = value
    @size &+= 1
    self
  end

  def <<(value : T) : self
    push(value)
  end

  def each(&) : Nil
    index = 0
    while index < @size
      yield self[index]
      index &+= 1
    end
  end

  def concat(source) : self
    source.each { |element| self << element }
    self
  end

  def map(& : T -> U) : Array(U) forall U
    result = Array(U).new
    each { |element| result << yield element }
    result
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
