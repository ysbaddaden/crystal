struct Int32
  def ===(other : self)
    self == other
  end

  def succ
    self + 1
  end

  def times(&block : Int32 ->) : Nil
    i = 0
    while i < self
      yield i
      i &+= 1
    end
  end

  def abs
    self < 0 ? 0 - self : self
  end
end

struct Int64
  def - : Int64
    0_i64 - self
  end
end

struct UInt32
  def self.new(other) : self
    other.to_u32
  end
end

struct UInt64
  def self.new(other) : self
    other.to_u64
  end
end
