require "../abi"

# Based on https://github.com/avr-rust/rust/blob/75c8395e72269d24c989cce624e3b63de80bdf7e/src/librustc_trans/cabi_avr.rs
class LLVM::ABI::AVR < LLVM::ABI
  def abi_info(atys : Array(Type), rty : Type, ret_def : Bool)
    ret_ty = compute_return_type(rty, ret_def)

    offset = ret_ty.kind.indirect? ? 4 : 0
    arg_tys = compute_arg_types(atys, offset)

    FunctionType.new(arg_tys, ret_ty)
  end

  def align(type : Type)
    case type.kind
    when Type::Kind::Integer
      (type.int_width + 7) / 8
    when Type::Kind::Pointer
      2
    when Type::Kind::Float
      4
    when Type::Kind::Double
      4
    when Type::Kind::Struct
      if type.packed_struct?
        1
      else
        type.struct_element_types.reduce(1) do |memo, element_type|
          Math.max(memo, align(element_type))
        end
      end
    when Type::Kind::Array
      align(type.element_type)
    else
      raise "Unhandled Type::Kind in align: #{type.kind}"
    end
  end

  def size(type : Type)
    case type.kind
    when Type::Kind::Integer
      (type.int_width + 7) / 8
    when Type::Kind::Pointer
      2
    when Type::Kind::Float
      4
    when Type::Kind::Double
      4
    when Type::Kind::Struct
      if type.packed_struct?
        type.struct_element_types.reduce(0) do |memo, element_type|
          memo + size(element_type)
        end
      else
        size = type.struct_element_types.reduce(0) do |memo, element_type|
          align_offset(memo, element_type) + size(element_type)
        end
        align_offset(size, type)
      end
    when Type::Kind::Array
      size(type.element_type) * type.array_size
    else
      raise "Unhandled Type::Kind in size: #{type.kind}"
    end
  end

  def register?(type)
    case type.kind
    when Type::Kind::Integer, Type::Kind::Float, Type::Kind::Double, Type::Kind::Pointer
      true
    else
      false
    end
  end

  private def compute_return_type(rty, ret_def)
    if !ret_def
      ArgType.direct(LLVM::Void)
    elsif register?(rty)
      non_struct(rty)
    else
      ArgType.indirect(rty, LLVM::Attribute::StructRet)
    end
  end

  private def compute_arg_types(atys, offset)
    atys.map do |aty|
      orig_offset = offset
      size = size(aty)
      align = align(aty).clamp(4, 8)

      offset = align_up_to(offset, align)
      offset += align_up_to(size, align * 8) / 8

      if register?(aty)
        non_struct(aty)
      else
        ArgType.direct(aty, cast: struct_type(aty), pad: padding(align, orig_offset))
      end
    end
  end

  private def non_struct(type)
    attr = type == LLVM::Int1 ? LLVM::Attribute::ZExt : nil
    ArgType.direct(type, attr: attr)
  end

  private def padding(align, offset)
    if ((align - 1) & offset) > 0
      LLVM::Type.int(32)
    end
  end

  private def coerce_to_int(size)
    args = [] of LLVM::Type

    n = size / 32
    while n > 0
      args << LLVM::Int32
      n -= 1
    end

    r = size % 32
    if r > 0
      args << LLVM::Type.int(r)
    end

    args
  end

  private def struct_type(type)
    size = size(type) * 8
    LLVM::Type.struct(coerce_to_int(size), packed: false)
  end
end
