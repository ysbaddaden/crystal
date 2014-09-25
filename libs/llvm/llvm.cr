require "./*"

module LLVM
  @@initialized = false

  def self.init_x86
    return if @@initialized
    @@initialized = true

    LibLLVM.initialize_x86_target_info
    LibLLVM.initialize_x86_target
    LibLLVM.initialize_x86_target_mc
    LibLLVM.initialize_x86_asm_printer
    # LibLLVM.link_in_jit
    LibLLVM.link_in_mc_jit
  end

  def self.dump(value)
    LibLLVM.dump_value value
  end

  def self.type_of(value)
    Type.new LibLLVM.type_of(value)
  end

  def self.type_kind_of(value)
    LibLLVM.get_type_kind(value)
  end

  def self.size_of(type)
    LibLLVM.size_of(type)
  end

  def self.constant?(value)
    LibLLVM.is_constant(value) != 0
  end

  def self.null(type)
    LibLLVM.const_null(type)
  end

  def self.pointer_null(type)
    LibLLVM.const_pointer_null(type)
  end

  def self.set_name(value, name)
    LibLLVM.set_value_name(value, name)
  end

  def self.add_attribute(value, attribute)
    LibLLVM.add_attribute value, attribute
  end

  def self.get_attribute(value)
    LibLLVM.get_attribute value
  end

  def self.set_thread_local(value, thread_local = true)
    LibLLVM.set_thread_local(value, thread_local ? 1 : 0)
  end

  def self.undef(type)
    LibLLVM.get_undef(type)
  end

  def self.int(type, value)
    LibLLVM.const_int(type, value.to_u64, 0)
  end

  def self.float(value : Float32)
    LibLLVM.const_real(LLVM::Float, value.to_f64)
  end

  def self.float(string : String)
    LibLLVM.const_real_of_string(LLVM::Float, string)
  end

  def self.double(value : Float64)
    LibLLVM.const_real(LLVM::Double, value)
  end

  def self.double(string : String)
    LibLLVM.const_real_of_string(LLVM::Double, string)
  end

  def self.set_linkage(value, linkage)
    LibLLVM.set_linkage(value, linkage)
  end

  def self.set_global_constant(value, flag)
    LibLLVM.set_global_constant(value, flag ? 1 : 0)
  end

  def self.array(type, values)
    LibLLVM.const_array(type, values, values.length.to_u32)
  end

  def self.struct(values, packed = false)
    LibLLVM.const_struct(values, values.length.to_u32, packed ? 1 : 0)
  end

  def self.string(string)
    LibLLVM.const_string(string.cstr, string.bytesize.to_u32, 0)
  end

  def self.set_initializer(value, initializer)
    LibLLVM.set_initializer(value, initializer)
  end

  def self.start_multithreaded
    if multithreaded?
      true
    else
      LibLLVM.start_multithreaded != 0
    end
  end

  def self.stop_multithreaded
    if multithreaded?
      LibLLVM.stop_multithreaded
    end
  end

  def self.multithreaded?
    LibLLVM.is_multithreaded != 0
  end

  def self.first_instruction(block)
    LibLLVM.get_first_instruction(block)
  end

  def self.delete_basic_block(block)
    LibLLVM.delete_basic_block(block)
  end

  def self.default_target_triple
    chars = LibLLVM.get_default_target_triple
    String.new(chars).tap { LibLLVM.dispose_message(chars) }
  end

  def self.to_io(chars, io)
    io.write Slice.new(chars, C.strlen(chars))
    LibLLVM.dispose_message(chars)
  end

  Void = Type.void
  Int1 = Type.int(1)
  Int8 = Type.int(8)
  Int16 = Type.int(16)
  Int32 = Type.int(32)
  Int64 = Type.int(64)
  Float = Type.float
  Double = Type.double

  VoidPointer = Int8.pointer

  # TODO: replace with constants after 0.5.0
  ifdef x86_64
    SizeT = Type.int(64) # Int64
  else
    SizeT = Type.int(32) # Int32
  end
end
