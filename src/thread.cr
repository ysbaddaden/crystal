require "c/pthread"
require "./thread/*"

# :nodoc:
class Thread
  # Don't use this class, it is used internally by the event scheduler.
  # Use spawn and channels instead.

  # all threads, so the GC can see them (GC doesn't scan thread locals)
  @@threads = Set(Thread).new
  @@threads_mutex = Thread::Mutex.new

  @th : LibC::PthreadT?
  @exception : Exception?
  @detached = false

  property current_fiber

  def initialize(&@func : ->)
    @current_fiber = uninitialized Fiber
    @@threads_mutex.synchronize { @@threads << self }
    @th = th = uninitialized LibC::PthreadT

    ret = GC.pthread_create(pointerof(th), Pointer(LibC::PthreadAttrT).null, ->(data : Void*) {
      (data.as(Thread)).start
      Pointer(Void).null
    }, self.as(Void*))
    @th = th

    if ret != 0
      raise Errno.new("pthread_create")
    end
  end

  def initialize
    @current_fiber = uninitialized Fiber
    @func = ->{}
    @@threads_mutex.synchronize { @@threads << self }
    @th = LibC.pthread_self
  end

  def finalize
    GC.pthread_detach(@th.not_nil!) unless @detached
  end

  def join
    GC.pthread_join(@th.not_nil!)
    @detached = true

    if exception = @exception
      raise exception
    end
  end

  {% if flag?(:android) || flag?(:openbsd) %}
    # no thread local storage (TLS) for OpenBSD or Android,
    # we use pthread's specific storage (TSS) instead:
    @@current_key = uninitialized LibC::PthreadKeyT

    ret = LibC.pthread_key_create(pointerof(@@current_key), nil)
    raise Errno.new("pthread_key_create") unless ret == 0

    def self.current : Thread
      if ptr = LibC.pthread_getspecific(@@current_key)
        ptr.as(Thread)
      else
        raise "BUG: Thread.current returned NULL"
      end
    end

    protected def self.current=(thread : Thread) : Thread
      ret = LibC.pthread_setspecific(@@current_key, thread.as(Void*))
      raise Errno.new("pthread_setspecific") unless ret == 0
      thread
    end

    self.current = new
  {% else %}
    @[ThreadLocal]
    @@current = new

    def self.current : Thread
      @@current
    end

    protected def self.current=(@@current : Thread) : Thread
    end
  {% end %}

  protected def start
    Thread.current = self
    begin
      @func.call
    rescue ex
      @exception = ex
    ensure
      @@threads_mutex.synchronize { @@threads.delete(self) }
    end
  end
end
