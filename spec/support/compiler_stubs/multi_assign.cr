require "./range_literal"
require "./tuple_constructor"

struct Tuple
  include Indexable(Union(*T))

  def size
    {{T.size}}
  end
end

class IndexError
  def initialize(message : String)
  end
end

lib LibC
  fun abort : NoReturn
end

# Successful execution examples never take the generated mismatch branch.
def raise(error : IndexError) : NoReturn
  LibC.abort
end
