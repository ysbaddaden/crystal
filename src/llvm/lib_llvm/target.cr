require "./types"

lib LibLLVM
  type TargetDataRef = Void*

  # The list of LLVM targets is found in llvm/Config/Target.def
  {% for name, target in {
                           "AArch64"     => "aarch64",
                           "ARM"         => "arm",
                           "AVR"         => "avr",
                           "WebAssembly" => "webassembly",
                           "X86"         => "x86",
                         } %}
    fun initialize_{{target.id}}_target_info = LLVMInitialize{{name.id}}TargetInfo
    fun initialize_{{target.id}}_target = LLVMInitialize{{name.id}}Target
    fun initialize_{{target.id}}_target_mc = LLVMInitialize{{name.id}}TargetMC
    fun initialize_{{target.id}}_asm_printer = LLVMInitialize{{name.id}}AsmPrinter
    fun initialize_{{target.id}}_asm_parser = LLVMInitialize{{name.id}}AsmParser
  {% end %}

  fun set_module_data_layout = LLVMSetModuleDataLayout(m : ModuleRef, dl : TargetDataRef)

  fun dispose_target_data = LLVMDisposeTargetData(td : TargetDataRef)
  fun size_of_type_in_bits = LLVMSizeOfTypeInBits(td : TargetDataRef, ty : TypeRef) : ULongLong
  fun abi_size_of_type = LLVMABISizeOfType(td : TargetDataRef, ty : TypeRef) : ULongLong
  fun abi_alignment_of_type = LLVMABIAlignmentOfType(td : TargetDataRef, ty : TypeRef) : UInt
  fun offset_of_element = LLVMOffsetOfElement(td : TargetDataRef, struct_ty : TypeRef, element : UInt) : ULongLong
  fun copy_string_rep_of_target_data = LLVMCopyStringRepOfTargetData(td : TargetDataRef) : Char*
end
