struct Pointer(T)
  def self.null
    new(0_u64)
  end

  def self.malloc(size : Int, value : T) : Pointer(T)
    buffer = Pointer(T).malloc(size.to_u64!)
    index = 0_i64
    while index < size
      (buffer + index).value = value
      index &+= 1
    end
    buffer
  end

  def null? : Bool
    address == 0
  end

  def []=(index : Int32, value : T) : T
    (self + index.to_i64!).value = value
  end

  def <(other : Pointer)
    address < other.address
  end
end
