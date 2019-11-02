module Debug2
  class ELF
    # :nodoc:
    class Reader
      getter io : IO::FileDescriptor
      property klass : CLASS
      property data : ENCODING

      def initialize(@io)
        @klass = CLASS::NONE
        @data = ENCODING::NONE
      end

      def read_magic
        magic = uninitialized UInt8[4]
        io.read(magic.to_slice)
        magic
      end

      def seek(offset)
        @io.seek(offset)
      end

      def seek(offset)
        @io.seek(offset) { yield }
      end

      def skip(n)
        @io.skip(n)
      end

      def read_addr
        read_ulong
      end

      def read_off
        read_ulong
      end

      def read_half
        @io.read_bytes(UInt16, byte_format)
      end

      def read_word
        @io.read_bytes(UInt32, byte_format)
      end

      def read_sword
        @io.read_bytes(Int32, byte_format)
      end

      def read_xword
        @io.read_bytes(UInt64, byte_format)
      end

      def read_sxword
        @io.read_bytes(Int64, byte_format)
      end

      def read_uchar
        @io.read_byte.not_nil!
      end

      def read_ulong
        case @klass
        when CLASS::ELF32 then read_word.to_u64
        when CLASS::ELF64 then read_xword
        else                   raise Error.new("Unsupported ELF class #{@klass}")
        end
      end

      def read_long
        case @klass
        when CLASS::ELF32 then read_sword.to_i64
        when CLASS::ELF64 then read_sxword
        else                   raise Error.new("Unsupported ELF class #{@klass}")
        end
      end

      def read_string
        @io.gets('\0', chomp: true).to_s
      end

      private def byte_format
        case @data
        when ENCODING::LSB then IO::ByteFormat::LittleEndian
        when ENCODING::MSB then IO::ByteFormat::BigEndian
        else                    raise Error.new("Unsupported ELF encoding #{@data}")
        end
      end
    end
  end
end
