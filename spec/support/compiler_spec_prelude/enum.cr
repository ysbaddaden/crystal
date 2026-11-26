# Case exhaustiveness specs only need the comparison result type.
struct Enum
  def ==(other : self)
    value == other.value
  end

  def ===(other)
    true
  end

  def includes?(other : self) : Bool
    (value & other.value) != 0
  end
end
