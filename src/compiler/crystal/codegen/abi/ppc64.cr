# Based on https://github.com/rust-lang/rust/blob/122cbd043833a1d7540cc5f99c458bfca2d3c525/compiler/rustc_target/src/callconv/powerpc64.rs
require "../abi"

class Crystal::ABI::PPC64 < Crystal::ABI
  ELFv1 = 1
  ELFv2 = 2

  # AIX not implemented

  def initialize(target_machine : LLVM::TargetMachine, @variant : Int32)
    super(target_machine)
  end

  def align(type : LLVM::Type) : Int32
    target_data.abi_alignment(type).to_i32
  end

  def size(type : LLVM::Type) : Int32
    target_data.abi_size(type).to_i32
  end

  def abi_info(atys : Array(LLVM::Type), rty : LLVM::Type, ret_def : Bool, context : LLVM::Context) : Crystal::ABI::FunctionType
    arg_tys = atys.map { |aty| classify(aty, context, is_ret: false) }
    ret_ty = compute_return_type(rty, ret_def, context)
    FunctionType.new(arg_tys, ret_ty)
  end

  private def compute_return_type(rty, ret_def, context)
    if ret_def
      classify(rty, context, is_ret: true)
    else
      ArgType.direct(context.void)
    end
  end

  private def classify(ty, context, is_ret)
    case ty.kind
    when LLVM::Type::Kind::Integer
      return extend_integer(ty, context)
    when LLVM::Type::Kind::Pointer, LLVM::Type::Kind::Double, LLVM::Type::Kind::Float
      return ArgType.direct(ty)
    end

    # The ELFv1 ABI doesn't return aggregates in registers.
    if is_ret && @variant == ELFv1
      return ArgType.indirect(ty, LLVM::Attribute::StructRet)
    end

    if agg = homogeneous_aggregate?(ty)
      uty, count = agg
      return ArgType.direct(ty, uty.array(count))
    end

    size = self.size(ty)
    bitsize = size * 8

    if is_ret && bitsize > 128
      # Non-homogeneous aggregates larger than two doublewords are returned
      # indirectly.
      ArgType.indirect(ty, LLVM::Attribute::StructRet)
    elsif bitsize <= 64
      # Aggregates smaller than a doubleword should appear in the
      # least-significant bits of the parameter doubleword.
      ArgType.direct(ty, cast: context.int64)
    else
      # Aggregates larger than i64 should be padded at the tail to fill out a
      # whole number of i64s or i128s, depending on the aggregate alignment.
      # Always use an array for this, even if there is only a single element.
      cast = align(ty) > 8 ? context.int128.array(1) : context.int64.array(2)
      ArgType.direct(ty, cast)
    end
  end

  private def extend_integer(ty, context)
    bitsize = ty.int_width

    if bitsize == 1
      ArgType.direct(ty, attr: LLVM::Attribute::ZExt)
    elsif bitsize < 64
      # Values shorter than a doubleword are sign or zero extended as necessary.
      # FIXME: set LLVM::Attribute::ZExt (unsigned) or LLVM::Attribute::SExt (signed)
      ArgType.direct(ty, cast: context.int64)
    else
      ArgType.direct(ty)
    end
  end

  # TODO: reduce duplication with ABI::AArch64
  private def homogeneous_aggregate?(ty) : {LLVM::Type, UInt64}?
    agg =
      case ty.kind
      when LLVM::Type::Kind::Float, LLVM::Type::Kind::Double
        return {ty, 1_u64}
      when LLVM::Type::Kind::Array
        homogeneous_array?(ty)
      when LLVM::Type::Kind::Struct
        homogeneous_struct?(ty)
      end
    return unless agg

    # ELFv1 allows 1 member
    # ELFv2 allows 8 members
    registers = @variant == ELFv1 ? 1 : 8
    agg if size(ty) <= size(agg[0]) * registers
  end

  private def homogeneous_array?(ty) : {LLVM::Type, UInt64}?
    count = ty.array_size.to_u64
    return if count == 0

    if agg = homogeneous_aggregate?(ty.element_type)
      {agg[0], count * agg[1]}
    end
  end

  private def homogeneous_struct?(ty) : {LLVM::Type, UInt64}?
    uty = nil
    count = 0_u64

    ty.struct_element_types.each do |ety|
      return unless agg = homogeneous_aggregate?(ety)

      if !uty
        # memorize first member
        uty, count = agg
      else
        # compare following members to the first
        return unless uty == agg[0]
        count += agg[1]
      end
    end
    return unless uty

    # check no padding
    if size(ty) == size(uty) * count
      {uty, count}
    end
  end
end
