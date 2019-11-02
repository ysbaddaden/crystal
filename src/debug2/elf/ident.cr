module Debug2
  class ELF
    enum OSABI : UInt8
      SYSTEM_V = 0x00
      HP_UX    = 0x01
      NETBSD   = 0x02
      LINUX    = 0x03
      SOLARIS  = 0x06
      AIX      = 0x07
      IRIX     = 0x08
      FREEBSD  = 0x09
      OPENBSD  = 0x0C
      OPENVMS  = 0x0D
      NSK_OS   = 0x0E
      AROS     = 0x0F
      FENIS_OS = 0x10
      CLOUDABI = 0x11
      SORTIX   = 0x53
    end

    struct Ident
      property klass : CLASS
      property data : ENCODING
      property version : UInt8
      property osabi : OSABI
      property abiversion : UInt8

      def self.read(reader : Reader) : self
        # read ELF file identification
        magic = reader.read_magic
        raise Error.new("Invalid magic number") unless magic == MAGIC

        # read ELF identification
        ei_class = CLASS.new(reader.read_uchar)
        ei_data = ENCODING.from_value(reader.read_uchar)
        ei_version = reader.read_uchar
        raise Error.new("Unsupported version number") unless ei_version == 1
        ei_osabi = OSABI.from_value(reader.read_uchar)
        ei_abiversion = reader.read_uchar
        reader.skip(7) # padding (unused)

        # configure reader to read the rest of the ELF file
        reader.klass = ei_class
        reader.data = ei_data

        # build ELF identification
        new(ei_class, ei_data, ei_version, ei_osabi, ei_abiversion)
      end

      def initialize(@klass, @data, @version, @osabi, @abiversion)
      end
    end
  end
end
