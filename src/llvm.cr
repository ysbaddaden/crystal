require "./llvm/**"
require "c/string"

module LLVM
  @@initialized = false

  private macro init(arch)
    def self.init_{{arch}}
      return if @@initialized_{{arch}}
      @@initialized_{{arch}} = true

      {% if LibLLVM::BUILT_TARGETS.includes?(arch.symbolize) %}
        LibLLVM.initialize_{{arch}}_target_info
        LibLLVM.initialize_{{arch}}_target
        LibLLVM.initialize_{{arch}}_target_mc
        LibLLVM.initialize_{{arch}}_asm_printer
        LibLLVM.initialize_{{arch}}_asm_parser
        # LibLLVM.link_in_jit
        LibLLVM.link_in_mc_jit
      {% else %}
        raise "ERROR: LLVM was built without {{arch.stringify.upcase.id}} target"
      {% end %}
    end
  end

  init aarch64
  init arm
  init avr
  init x86

  def self.int(type, value) : Value
    Value.new LibLLVM.const_int(type, value, 0)
  end

  def self.float(value : Float32) : Value
    Value.new LibLLVM.const_real(LLVM::Float, value)
  end

  def self.float(string : String) : Value
    Value.new LibLLVM.const_real_of_string(LLVM::Float, string)
  end

  def self.double(value : Float64) : Value
    Value.new LibLLVM.const_real(LLVM::Double, value)
  end

  def self.double(string : String) : Value
    Value.new LibLLVM.const_real_of_string(LLVM::Double, string)
  end

  def self.array(type, values : Array(LLVM::Value)) : Value
    Value.new LibLLVM.const_array(type, (values.to_unsafe.as(LibLLVM::ValueRef*)), values.size)
  end

  def self.struct(values : Array(LLVM::Value), packed = false) : Value
    Value.new LibLLVM.const_struct((values.to_unsafe.as(LibLLVM::ValueRef*)), values.size, packed ? 1 : 0)
  end

  def self.string(string) : Value
    Value.new LibLLVM.const_string(string, string.bytesize, 0)
  end

  def self.start_multithreaded : Bool
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

  def self.multithreaded? : Bool
    LibLLVM.is_multithreaded != 0
  end

  def self.default_target_triple : String
    chars = LibLLVM.get_default_target_triple
    triple = string_and_dispose(chars)
    if triple =~ /x86_64-apple-macosx|x86_64-apple-darwin/
      "x86_64-apple-macosx"
    else
      triple
    end
  end

  def self.to_io(chars, io)
    io.write Slice.new(chars, LibC.strlen(chars))
    LibLLVM.dispose_message(chars)
  end

  def self.const_inline_asm(type, asm_string, constraints, has_side_effects = false, is_align_stack = false)
    Value.new LibLLVM.const_inline_asm(type, asm_string, constraints, (has_side_effects ? 1 : 0), (is_align_stack ? 1 : 0))
  end

  def self.string_and_dispose(chars) : String
    string = String.new(chars)
    LibLLVM.dispose_message(chars)
    string
  end

  Void   = Type.new LibLLVM.void_type
  Int1   = Type.new LibLLVM.int1_type
  Int8   = Type.new LibLLVM.int8_type
  Int16  = Type.new LibLLVM.int16_type
  Int32  = Type.new LibLLVM.int32_type
  Int64  = Type.new LibLLVM.int64_type
  Float  = Type.new LibLLVM.float_type
  Double = Type.new LibLLVM.double_type

  VoidPointer = Int8.pointer

  {% if flag?(:x86_64) || flag?(:aarch64) %}
    SizeT = Int64
  {% else %}
    SizeT = Int32
  {% end %}
end
