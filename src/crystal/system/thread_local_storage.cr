# :nodoc:
class Thread
  # :nodoc:
  struct LocalStorage
    alias Destructor = Proc(Void*, Nil)

    def self.get(key : Key, &) : Void*
      get(key) || set(key, yield.as(Void*))
    end

    {% if flag?(:android) || flag?(:openbsd) %}
      alias Key = LibC::PthreadKeyT

      def self.create(destructor : Destructor? = nil) : Key
        LibC.pthread_key_create(out key, destructor)
        raise RuntimeError.from_os_error("pthread_key_create", Errno.new(err)) unless err == 0
        key
      end

      def self.get(key : Key) : Void*
        LibC.pthread_getspecific(key)
      end

      def self.set(key : Key, value : Void*) : Void*
        err = LibC.pthread_setspecific(key, value)
        raise RuntimeError.from_os_error("pthread_setspecific", Errno.new(err)) unless err == 0
        value
      end

      @[AlwaysInline]
      def self.call_destructors : Nil
      end
    {% elsif flag?(:win32) && flag?(:gnu) %}
      alias Key = LibC::DWORD

      def self.create(destructor : Destructor? = nil) : Key
        key = LibC.FlsAlloc(nil)
        raise RuntimeError.from_winerror("FlsAlloc: out of indexes") if key == LibC::FLS_OUT_OF_INDEXES
        key
      end

      def self.get(key : Key) : Void*
        LibC.FlsGetValue(key)
      end

      def self.set(key : Key, value : Void*) : Void*
        ret = LibC.FlsSetValue(key, value)
        raise RuntimeError.from_winerror("FlsSetValue") if ret == 0
        value
      end

      def self.call_destructors : Nil
      end
    {% else %}
      alias Key = Int32

      FREE = Destructor.new(Pointer(Void).null, Pointer(Void).null)
      RESERVED = Destructor.new(Pointer(Void).new(-1.to_u64!), Pointer(Void).null)

      @[ThreadLocal]
      @@instance = uninitialized Pointer(self)

      @@mutex = Thread::Mutex.new
      @@destructors = Pointer(Destructor).null
      @@size = 0

      def self.instance=(@@instance : Pointer(self)) : Pointer(self)
        @@instance
      end

      def self.create(destructor : Destructor? = nil) : Key
        @@mutex.synchronize do
          key = nil

          0.upto(@@size - 1) do |i|
            if @@destructors[i] == FREE
              key = i
              break
            end
          end

          unless key
            # full: must grow
            key = @@size # == 0 ? 1 : @@size
            new_size = Math.pw2ceil(key.clamp(4..))
            @@destructors = GC.realloc(@@destructors.as(Void*), sizeof(Destructor) * new_size).as(Destructor*)
            @@size = new_size
          end

          if destructor
            @@destructors[key] = destructor
          else
            @@destructors[key] = RESERVED
          end

          key
        end
      end

      def self.delete(key : Key) : Void*
        @@mutex.synchronize do
          raise RuntimeError.new("Invalid key") unless 0 <= key < @@size
        end
      end

      def self.get(key : Key) : Void*
        @@instance.value.get(key)
      end

      def self.set(key : Key, value : Void*) : Void*
        @@instance.value.set(key, value)
      end

      def self.call_destructors : Nil
        @@instance.value.call_destructors
      end

      def initialize
        @values = Pointer(Void*).null
        @size = 0
      end

      protected def get(key : Key) : Void*
        if 0 <= key < @size
          @values[key]
        else
          Pointer(Void).null
        end
      end

      protected def set(key : Key, value : Void*) : Void*
        keys = @@size
        raise RuntimeError.new("Invalid key") unless 0 <= key < keys

        unless key < @size
          # grow storage table
          @values = GC.realloc(@values.as(Void*), sizeof(Void*) * keys).as(Void**)
          @size = keys
        end

        @values[key] = value
      end

      protected def call_destructors : Nil
        return if @values.null? || @@destructors.null?

        @@mutex.synchronize do
          @@size.times do |key|
            destructor = @@destructors[key]
            next if destructor == FREE || destructor == RESERVED
            next if (value = get(key)).null?

            @values[key] = Pointer(Void).null
            destructor.call(value)
          end

          @values = Pointer(Void*).null
          @size = 0
        end
      end

    {% end %}
  end
end
