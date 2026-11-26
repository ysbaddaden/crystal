require "./array_literal"
require "./array_access"

# Supports tuple splats in array literals during semantic analysis.
struct Tuple
  def each(& : Union(*T) ->) : Nil
    {% for i in 0...T.size %}
      yield self[{{i}}]
    {% end %}
  end
end

lib LibC
  fun exit(status : Int32) : NoReturn
end

module Enumerable(T)
  def self.element_type(source)
    source.each { |element| return element }
    LibC.exit(1)
  end
end

class Array(T)
  def concat(source) : self
    source.each { |element| self << element }
    self
  end
end
