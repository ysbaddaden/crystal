module Indexable(T)
  def [](index : Int)
    unsafe_fetch(index)
  end
end
