require "zlib"

module Debug2
  class ELF
    struct SectionHeader
      enum Type : UInt32
        NULL          =  0
        PROGBITS      =  1
        SYMTAB        =  2
        STRTAB        =  3
        RELA          =  4
        HASH          =  5
        DYNAMIC       =  6
        NOTE          =  7
        NOBITS        =  8
        REL           =  9
        SHLIB         = 10
        DYNSYM        = 11
        INIT_ARRAY    = 14
        FINI_ARRAY    = 15
        PREINIT_ARRAY = 16
        GROUP         = 17
        SYMTAB_SHNDX  = 18
      end

      @[Flags]
      enum Flags : UInt64
        WRITE            =        0x1
        ALLOC            =        0x2
        EXECINSTR        =        0x4
        MERGE            =       0x10
        STRINGS          =       0x20
        INFO_LINK        =       0x40
        LINK_ORDER       =       0x80
        OS_NONCONFORMING =      0x100
        GROUP            =      0x200
        TLS              =      0x400
        COMPRESSED       =      0x800
        MASKOS           = 0x0ff00000
        MASKPROC         = 0xf0000000
      end

      property name : UInt32
      property type : Type
      property flags : Flags
      property addr : UInt64
      property offset : UInt64
      property size : UInt64
      property link : UInt32
      property info : UInt32
      property addralign : UInt64
      property entsize : UInt64

      def self.read(reader : Reader) : self
        sh_name = reader.read_word
        sh_type = Type.new(reader.read_word)
        sh_flags = Flags.new(reader.read_ulong)
        sh_addr = reader.read_addr
        sh_offset = reader.read_off
        sh_size = reader.read_ulong
        sh_link = reader.read_word
        sh_info = reader.read_word
        sh_addralign = reader.read_ulong
        sh_entsize = reader.read_ulong

        new(sh_name, sh_type, sh_flags, sh_addr, sh_offset, sh_size, sh_link, sh_info, sh_addralign, sh_entsize)
      end

      def initialize(@name, @type, @flags, @addr, @offset, @size, @link, @info, @addralign, @entsize)
      end
    end

    struct CompressionHeader
      enum Type : UInt32
        ZLIB   = 1_u32
        LOOS   = 0x60000000_u32
        HIOS   = 0x6fffffff_u32
        LOPROC = 0x70000000_u32
        HIPROC = 0x7fffffff_u32
      end

      property type : Type
      property size : UInt64
      property addralign : UInt64

      def self.read(reader : Reader) : self
        ch_type = Type.new(reader.read_word)
        ch_reserved = reader.read_word if reader.klass == CLASS::ELF64
        ch_size = reader.read_ulong
        ch_addralign = reader.read_ulong

        new(ch_type, ch_size, ch_addralign)
      end

      def initialize(@type, @size, @addralign)
      end
    end
  end
end
