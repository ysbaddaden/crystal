{% skip_file unless flag?(:unix) %}

require "c/sys/mman"

module Crystal::System
  # :nodoc:
  struct MemoryMapping
    enum Protection
      NONE = LibC::PROT_NONE
      READ = LibC::PROT_READ
      WRITE = LibC::PROT_WRITE
      READ_WRITE = LibC::PROT_READ | LibC::PROT_WRITE
    end

    @[Flags]
    enum Flags
      STACK
    end

    @[Flags]
    enum Advice
      {% if flag?(:linux) %}
        NOHUGEPAGE = LibC::MADV_NOHUGEPAGE
      {% else %}
        NOHUGEPAGE = 0
      {% end %}
    end

    getter size : LibC::SizeT
    getter pointer : Void*

    def initialize(size, protection : Protection, flags : Flags = :NONE)
      @size = LibC::SizeT.new(size)

      flags = LibC::MAP_ANONYMOUS | LibC::MAP_PRIVATE
      {% if LibC.constants.includes?(:MAP_STACK.id) %}
        flags |= LibC::MAP_STACK if flags.stack?
      {% end %}

      @pointer = LibC.mmap(nil, size, protection, flags, -1, 0)
      raise Errno.new("mmap") if @pointer == LibC::MAP_FAILED
    end

    def free : Nil
      ret = LibC.munmap(@pointer, @size)
      raise Errno.new("munmap") unless ret == 0
    end

    def advise(advices : Advice) : Nil
      return if advices.none?
      ret = LibC.madvise(pointer, size, advices)
      raise Errno.new("madvise") unless ret == 0
    end

    def protect(guard_size, protection : Protection = :NONE) : Nil
      ret = LibC.mprotect(@pointer, guard_size, protection)
      raise Errno.new("mprotect") unless ret == 0
    end
  end
end
