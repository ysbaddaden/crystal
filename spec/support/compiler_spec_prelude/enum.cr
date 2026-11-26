# Case exhaustiveness specs only need the comparison result type.
struct Enum
  def ==(other : self)
    value == other.value
  end

  def ===(other)
    true
  end
end
