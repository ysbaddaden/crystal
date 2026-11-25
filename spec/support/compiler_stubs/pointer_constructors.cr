struct Pointer(T)
  def self.null
    new(0_u64)
  end

  def self.malloc(size : Int, value : T) : Pointer(T)
    Pointer(T).null
  end
end
