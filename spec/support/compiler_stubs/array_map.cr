require "./array_literal"
require "./array_access"

# Preserves the block and result types for semantic specs.
class Array(T)
  def map(& : T -> U) : Array(U) forall U
    [yield self[0]]
  end
end
