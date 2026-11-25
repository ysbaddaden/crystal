# Preserves array element types in semantic-only inputs.
class Array(T)
  def <<(value : T) : self
    self
  end

  def [](index : Int) : T
    element = uninitialized T
    element
  end
end
