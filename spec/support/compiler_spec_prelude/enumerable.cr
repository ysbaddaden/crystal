require "./lib_c"
require "./array"

module Enumerable(T)
  def map(& : T -> U) : Array(U) forall U
    result = Array(U).new
    each { |element| result << yield element }
    result
  end

  def self.element_type(source)
    source.each { |element| return element }
    LibC.exit(1)
  end
end
