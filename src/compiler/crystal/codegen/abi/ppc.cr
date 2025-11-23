# Based on https://github.com/rust-lang/rust/blob/d3e1ccdf40ae7b7a6dc81edc073d80dad7b66f75/compiler/rustc_target/src/callconv/powerpc.rs
require "../abi"

class Crystal::ABI::PPC < Crystal::ABI
  def initialize(target_machine : LLVM::TargetMachine)
    @linux = target_machine.triple =~ /-linux-(?:musl|gnu|uclibc)/
    super(target_machine)
  end

  def align(type : LLVM::Type) : Int32
    target_data.abi_alignment(type).to_i32
  end

  def size(type : LLVM::Type) : Int32
    target_data.abi_size(type).to_i32
  end

  def abi_info(atys : Array(LLVM::Type), rty : LLVM::Type, ret_def : Bool, context : LLVM::Context) : Crystal::ABI::FunctionType
    arg_tys = atys.map { |aty| compute_arg_type(aty, context) }
    ret_ty = compute_return_type(rty, ret_def, context)
    FunctionType.new(arg_tys, ret_ty)
  end

  private def compute_arg_type(aty, context)
    if size(aty) == 0
      if @linux
        ArgType.indirect(aty, LLVM::Attribute::ByVal)
      else
        ArgType.ignore(aty)
      end
    else
      classify(aty, context, is_ret: false)
    end
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
      extend_integer(ty, context)
    when LLVM::Type::Kind::Pointer, LLVM::Type::Kind::Double, LLVM::Type::Kind::Float
      ArgType.direct(ty)
    else
      attr = is_ret ? LLVM::Attribute::StructRet : LLVM::Attribute::ByVal
      ArgType.indirect(ty, attr)
    end
  end

  private def extend_integer(ty, context)
    bitsize = ty.int_width

    if bitsize == 1
      ArgType.direct(ty, attr: LLVM::Attribute::ZExt)
    elsif bitsize < 32
      # Values shorter than a word are sign or zero extended as necessary.
      # FIXME: set LLVM::Attribute::ZExt (unsigned) or LLVM::Attribute::SExt (signed)
      ArgType.direct(ty, cast: context.int32)
    else
      ArgType.direct(ty)
    end
  end
end
