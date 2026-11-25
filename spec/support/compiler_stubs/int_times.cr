struct Int32
  def times(&block : Int32 ->) : Nil
    i = 0
    while i < self
      yield i
      i &+= 1
    end
  end
end
