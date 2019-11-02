require "./elf/*"

module Debug2
  class ELF
    class Error < Exception
    end

    MAGIC = UInt8.static_array(0x7f, 'E'.ord, 'L'.ord, 'F'.ord)

    enum CLASS : UInt8
      NONE = 0
      ELF32 = 1
      ELF64 = 2
    end

    enum ENCODING
      NONE = 0
      LSB = 1
      MSB = 2
    end

    enum TYPE : UInt16
      REL  = 1
      EXEC = 2
      DYN  = 3
      CORE = 4
    end

    enum MACHINE : UInt16
      UNKNOWN = 0x00
      SPARC   = 0x02
      X86     = 0x03
      MIPS    = 0x08
      POWERPC = 0x14
      ARM     = 0x28
      SUPERH  = 0x2A
      IA_64   = 0x32
      X86_64  = 0x3E
      AARCH64 = 0xB7
    end

    struct Header
      property type : TYPE
      property machine : MACHINE
      property version : UInt32
      property entry : UInt64
      property phoff : UInt64
      property shoff : UInt64
      property flags : UInt32
      property ehsize : UInt16
      property phentsize : UInt16
      property phnum : UInt16
      property shentsize : UInt16
      property shnum : UInt16
      property shstrndx : UInt16

      def self.read(reader : Reader) : self
        e_type = TYPE.new(reader.read_half)
        e_machine = MACHINE.new(reader.read_half)

        e_version = reader.read_word
        raise Error.new("Unsupported version number") unless e_version == 1

        e_entry = reader.read_addr
        e_phoff = reader.read_off
        e_shoff = reader.read_off

        e_flags = reader.read_word

        e_ehsize = reader.read_half
        case reader.klass
        when CLASS::ELF32 then raise Error.new("Header should be 52 bytes for ELF32") unless e_ehsize == 52
        when CLASS::ELF64 then raise Error.new("Header should be 64 bytes for ELF64") unless e_ehsize == 64
        else                   raise Error.new("Unsupported ELF class #{reader.klass}")
        end

        e_phentsize = reader.read_half
        e_phnum = reader.read_half

        e_shentsize = reader.read_half
        e_shnum = reader.read_half
        e_shstrndx = reader.read_half

        new(e_type, e_machine, e_version, e_entry, e_phoff, e_shoff, e_flags, e_ehsize, e_phentsize, e_phnum, e_shentsize, e_shnum, e_shstrndx)
      end

      def initialize(@type, @machine, @version, @entry, @phoff, @shoff, @flags, @ehsize, @phentsize, @phnum, @shentsize, @shnum, @shstrndx)
      end
    end

    @reader : Reader
    property ident : Ident
    property header : Header
    property section_headers : Array(SectionHeader)
    property section_names : Array(String)?

    def self.read(io : IO::FileDescriptor) : self
      reader = Reader.new(io)

      e_ident = Ident.read(reader)
      e_header = Header.read(reader)

      section_headers = Array(SectionHeader).new(e_header.shnum.to_i) do |i|
        reader.seek(e_header.shoff + i * e_header.shentsize)
        SectionHeader.read(reader)
      end

      new(reader, e_ident, e_header, section_headers)
    end

    def initialize(@reader, @ident, @header, @section_headers)
    end

    def section_names
      @section_names ||= begin
        shstr = @section_headers[header.shstrndx]
        @section_headers.map do |sh|
          @reader.seek(shstr.offset + sh.name) { @reader.read_string }
        end
      end
    end

    def read_section?(name : String, decompress = true)
      if number = section_names.index(name)
        read_section?(number, decompress) { |sh, io| yield sh, io }
      end
    end

    def read_section?(number : Int32, decompress = true)
      sh = section_headers[number]

      @reader.seek(sh.offset) do
        io = @reader.io

        if decompress && sh.flags.includes?(SectionHeader::Flags::COMPRESSED)
          ch = CompressionHeader.read(@reader)

          if ch.type == CompressionHeader::Type::ZLIB
            io = Zlib::Reader.new(io, sync_close: false)
            sh.size = ch.size
            sh.addralign = ch.addralign
          end
        end

        # read whole section into memory
        slice = Bytes.new(sh.size)
        io.read_fully(slice)

        yield sh, IO::Memory.new(slice, writeable: false)
      end
    end

    def each_section
      section_headers.each_with_index do |sh, number|
        yield section_names[number], sh, number
      end
    end
  end
end
