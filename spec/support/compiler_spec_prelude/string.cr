require "./lib_c"

class String
  # Only the inferred result type is needed by the semantic specs.
  def self.interpolation(*values) : String
    ""
  end

  def to_unsafe : UInt8*
    pointerof(@c)
  end

  def ==(other : String) : Bool
    LibC.strcmp(to_unsafe, other.to_unsafe) == 0
  end
end
