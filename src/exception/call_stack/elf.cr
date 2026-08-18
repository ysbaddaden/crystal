require "crystal/system/unix/elf"
{% unless flag?(:wasm32) %}
  require "c/link"
{% end %}

struct Exception::CallStack
  DEBUG_LINE_STR = ".debug_line_str"
  DEBUG_STR      = ".debug_str"
  DEBUG_LINE     = ".debug_line"
  DEBUG_ABBREV   = ".debug_abbrev"
  DEBUG_INFO     = ".debug_info"

  @@base_address = LibC::Elf_Addr.zero

  private struct DlPhdrData
    getter program : String
    property base_address : LibC::Elf_Addr = 0

    def initialize(@program : String)
    end
  end

  protected def self.load_debug_info_impl : Nil
    return unless path = Process.executable_path
    return unless program = Crystal::System::ELF.open(path)

    load_base_address(path)
    preload_dwarf_sections(program)
  end

  # Determine the address offset at which the program was loaded at.
  #
  # FIXME: depends on a dynamic loader, it may not work with static executables,
  # for example musl-libc.
  private def self.load_base_address(path)
    data = DlPhdrData.new(path)

    phdr_callback = LibC::DlPhdrCallback.new do |info, size, data|
      # `dl_iterate_phdr` does not always visit the current program first; on
      # Android the first object is `/system/bin/linker64`, the second is the
      # full program path (not the empty string), so we check both here
      name_c_str = info.value.name
      if name_c_str && (name_c_str.value == 0 || LibC.strcmp(name_c_str, data.as(DlPhdrData*).value.program) == 0)
        # The first entry is the header for the current program.
        data.as(DlPhdrData*).value.base_address = info.value.addr
        1
      else
        0
      end
    end

    LibC.dl_iterate_phdr(phdr_callback, pointerof(data))
    @@base_address = data.base_address
  end

  protected def self.decode_address(ip)
    if ip.null?
      ip.address
    else
      ip.address &- @@base_address
    end
  end

  protected def self.recode_address(pc)
    Pointer(Void).new(pc &+ @@base_address)
  end
end
