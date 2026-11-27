class String
  def self.interpolation(*values) : String
    # Only the inferred result type is needed by the semantic specs.
    ""
  end

  def to_unsafe : UInt8*
    pointerof(@c)
  end

  def ==(other : String) : Bool
    LibC.strcmp(to_unsafe, other.to_unsafe) == 0
  end

  def self.new(ptr : UInt8*, bytesize : Int32) : String
    ptr.as(Pointer(typeof(crystal_instance_type_id))).value = crystal_instance_type_id # set_crystal_type_id
    str = ptr.as(String)
    str.initialize_header(bytesize)
    str
  end

  def initialize_header(@bytesize : Int32, @length : Int32 = 0)
  end
end
