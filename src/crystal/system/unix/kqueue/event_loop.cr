require "../evented/event_loop"
require "../kqueue"

class Crystal::Kqueue::EventLoop < Crystal::Evented::EventLoop
  INTERRUPT_IDENTIFIER = 9

  {% unless LibC.has_constant?(:EVFILT_USER) %}
    @pipe = uninitialized LibC::Int[2]
  {% end %}

  def initialize
    super

    # the kqueue instance
    @kqueue = System::Kqueue.new

    # notification to interrupt a run
    @interrupted = Atomic::Flag.new
    {% unless LibC.has_constant?(:EVFILT_USER) %}
      @pipe = System::FileDescriptor.system_pipe
      @kqueue.kevent(@pipe[0], LibC::EVFILT_READ, LibC::EV_ADD) do
        raise RuntimeError.from_errno("kevent")
      end
    {% end %}
  end

  def after_fork_before_exec : Nil
    super

    # O_CLOEXEC would close these automatically but we don't want to mess with
    # the parent process fds (that would mess the parent evloop)

    # kqueue isn't inherited by fork on darwin/dragonfly, but we still close
    @kqueue.close

    {% unless LibC.has_constant?(:EVFILT_USER) %}
      @pipe.each { |fd| LibC.close(fd) }
    {% end %}
  end

  {% unless flag?(:preview_mt) %}
    def after_fork : Nil
      super

      # kqueue isn't inherited by fork on darwin/dragonfly, but we still close
      @kqueue.close
      @kqueue = System::Kqueue.new

      @interrupted.clear
      {% unless LibC.has_constant?(:EVFILT_USER) %}
        @pipe.each { |fd| LibC.close(fd) }
        @pipe = System::FileDescriptor.system_pipe
        @kqueue.kevent(@pipe[0], LibC::EVFILT_READ, LibC::EV_ADD) do
          raise RuntimeError.from_errno("kevent")
        end
      {% end %}

      system_set_timer(@timers.next_ready?)

      # re-add all registered fds
      Evented.arena.each { |fd, index| system_add(fd, index) }
    end
  {% end %}

  private def system_run(blocking : Bool) : Nil
    buffer = uninitialized LibC::Kevent[128]

    Crystal.trace :evloop, "run", blocking: blocking ? 1 : 0
    timeout = blocking ? nil : Time::Span.zero
    kevents = @kqueue.wait(buffer.to_slice, timeout)

    timer_triggered = false

    # process events
    kevents.size.times do |i|
      kevent = kevents.to_unsafe + i

      if process_interrupt?(kevent)
        # nothing special
      elsif kevent.value.filter == LibC::EVFILT_TIMER
        # nothing special
        timer_triggered = true
      else
        process(kevent)
      end
    end

    process_timers(timer_triggered)
  end

  private def process_interrupt?(kevent)
    {% if LibC.has_constant?(:EVFILT_USER) %}
      if kevent.value.filter == LibC::EVFILT_USER
        @interrupted.clear if kevent.value.ident == INTERRUPT_IDENTIFIER
        return true
      end
    {% else %}
      if kevent.value.filter == LibC::EVFILT_READ && kevent.value.ident == @pipe[0]
        @interrupted.clear
        byte = 0_u8
        ret = LibC.read(@pipe[0], pointerof(byte), 1)
        raise RuntimeError.from_errno("read") if ret == -1
        return true
      end
    {% end %}
    false
  end

  private def process(kevent : LibC::Kevent*) : Nil
    index =
      {% if flag?(:bits64) %}
        Evented::Arena::Index.new(kevent.value.udata.address)
      {% else %}
        # assuming 32-bit target: rebuild the arena index
        Evented::Arena::Index.new(kevent.value.ident.to_i32!, kevent.value.udata.address.to_u32!)
      {% end %}

    Crystal.trace :evloop, "event", fd: kevent.value.ident, index: index.to_i64,
      filter: kevent.value.filter, flags: kevent.value.flags, fflags: kevent.value.fflags

    pd = Evented.arena.get(index)

    if (kevent.value.fflags & LibC::EV_EOF) == LibC::EV_EOF
      # apparently some systems may report EOF on write with EVFILT_READ instead
      # of EVFILT_WRITE, so let's wake all waiters:
      pd.value.@readers.consume_each { |event| resume_io(event) }
      pd.value.@writers.consume_each { |event| resume_io(event) }
      return
    end

    case kevent.value.filter
    when LibC::EVFILT_READ
      if (kevent.value.fflags & LibC::EV_ERROR) == LibC::EV_ERROR
        # OPTIMIZE: pass errno (kevent.data) through PollDescriptor
        pd.value.@readers.consume_each { |event| resume_io(event) }
      elsif event = pd.value.@readers.ready!
        resume_io(event)
      end
    when LibC::EVFILT_WRITE
      if (kevent.value.fflags & LibC::EV_ERROR) == LibC::EV_ERROR
        # OPTIMIZE: pass errno (kevent.data) through PollDescriptor
        pd.value.@writers.consume_each { |event| resume_io(event) }
      elsif event = pd.value.@writers.ready!
        resume_io(event)
      end
    end
  end

  def interrupt : Nil
    return unless @interrupted.test_and_set

    {% if LibC.has_constant?(:EVFILT_USER) %}
      @kqueue.kevent(
        INTERRUPT_IDENTIFIER,
        LibC::EVFILT_USER,
        LibC::EV_ADD | LibC::EV_ONESHOT,
        LibC::NOTE_FFCOPY | LibC::NOTE_TRIGGER | 1_u16)
    {% else %}
      byte = 1_u8
      ret = LibC.write(@pipe[1], pointerof(byte), sizeof(typeof(byte)))
      raise RuntimeError.from_errno("write") if ret == -1
    {% end %}
  end

  protected def system_add(fd : Int32, index : Evented::Arena::Index) : Nil
    Crystal.trace :evloop, "kevent", op: "add", fd: fd, index: index.to_i64

    # register both read and write events
    kevents = uninitialized LibC::Kevent[2]
    2.times do |i|
      kevent = kevents.to_unsafe + i
      filter = i == 0 ? LibC::EVFILT_READ : LibC::EVFILT_WRITE

      udata =
        {% if flag?(:bits64) %}
          Pointer(Void).new(index.to_u64)
        {% else %}
          # assuming 32-bit target: pass the generation as udata (ident is the fd/index)
          Pointer(Void).new(index.generation)
        {% end %}
      System::Kqueue.set(kevent, fd, filter, LibC::EV_ADD | LibC::EV_CLEAR, udata: udata)
    end

    @kqueue.kevent(kevents.to_slice) do
      raise RuntimeError.from_errno("kevent")
    end
  end

  protected def system_del(fd : Int32, closing = true) : Nil
    system_del(fd, closing) do
      raise RuntimeError.from_errno("kevent")
    end
  end

  protected def system_del(fd : Int32, closing = true, &) : Nil
    return if closing # nothing to do: close(2) will do the cleanup

    Crystal.trace :evloop, "kevent", op: "del", fd: fd

    # unregister both read and write events
    kevents = uninitialized LibC::Kevent[2]
    2.times do |i|
      kevent = kevents.to_unsafe + i
      filter = i == 0 ? LibC::EVFILT_READ : LibC::EVFILT_WRITE
      System::Kqueue.set(kevent, fd, filter, LibC::EV_DELETE)
    end

    @kqueue.kevent(kevents.to_slice) do
      raise RuntimeError.from_errno("kevent")
    end
  end

  private def system_set_timer(time : Time::Span?) : Nil
    if time
      flags = LibC::EV_ADD | LibC::EV_ONESHOT | LibC::EV_CLEAR
      t = time - Time.monotonic
      data =
        {% if LibC.has_constant?(:NOTE_NSECONDS) %}
          t.total_nanoseconds.to_i64!.clamp(0..)
        {% else %}
          # legacy BSD (and DragonFly) only have millisecond precision
          t.positive? ? t.total_milliseconds.to_i64!.clamp(1..) : 0
        {% end %}
    else
      flags = LibC::EV_DELETE
      data = 0_u64
    end

    fflags =
      {% if LibC.has_constant?(:NOTE_NSECONDS) %}
        LibC::NOTE_NSECONDS
      {% else %}
        0
      {% end %}

    # use the evloop address as the unique identifier for the timer kevent
    ident = LibC::SizeT.new!(self.as(Void*).address)
    @kqueue.kevent(ident, LibC::EVFILT_TIMER, flags, fflags, data) do
      raise RuntimeError.from_errno("kevent") unless Errno.value == Errno::ENOENT
    end
  end
end
