{% skip_file unless flag?(:win32) %}

require "c/winbase"
require "c/winnt"

module Crystal::System
  # :nodoc:
  struct MemoryMapping
    enum Protection
      NONE = LibC::PAGE_NOACCESS
      READ = LibC::PAGE_READONLY
      WRITE = LibC::PAGE_WRITEONLY
      READ_WRITE = LibC::PAGE_READWRITE
    end

    @[Flags]
    enum Flags
      STACK
    end

    @[Flags]
    enum Advice
      NOHUGEPAGE = 0
    end

    getter size : LibC::SizeT
    getter pointer : Void*

    def initialize(size, protection : Protection, flags : Flags = :NONE)
      @size = LibC::SizeT.new(size)

      @pointer = LibC.VirtualAlloc(nil, @size, LibC::MEM_COMMIT | LibC::MEM_RESERVE, protection)
      raise WinError.new("VirtualAlloc") unless @pointer
    end

    def free : Nil
      ret = LibC.VirtualFree(@pointer, @size, LibC::MEM_RELEASE)
      raise WinError.new("VirtualFree") unless ret == 0
    end

    def advise(advices : Advice) : Nil
      # noop
    end

    def protect(guard_size, protection : Protection = :NONE) : Nil
      ret = LibC.VirtualProtect(@pointer, guard_size, protection)
      raise WinError.new("VirtualProtect") unless ret == 0
    end
  end
end
