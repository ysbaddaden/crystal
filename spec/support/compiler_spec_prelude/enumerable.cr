require "./lib_c"

module Enumerable(T)
  def self.element_type(source)
    source.each { |element| return element }
    LibC.exit(1)
  end
end
