# forward declaration for the require below to not create a module
class Crystal::EventLoop::IoUring < Crystal::EventLoop
end

require "c/poll"
require "c/sys/socket"
require "./io_uring/*"

{% if flag?(:execution_context) %}
  class Fiber::ExecutionContext::Scheduler
    # :nodoc:
    property! __evloop_ring : Crystal::EventLoop::Ring
  end
{% end %}

# NOTE: IOSQE_CQE_SKIP_SUCCESS is incompatible with IOSQE_IO_DRAIN!

class Crystal::EventLoop::IoUring < Crystal::EventLoop
  def self.default_file_blocking?
    false
  end

  def self.default_socket_blocking?
    false
  end

  # While io_uring was introduced in Linux 5.1, some features and opcodes that
  # we require have only been added between Linux 5.3 to 5.18. The event loop is
  # thus incompatible with:
  #
  # - Linux 5.4 LTS (EOL Dec 2025)
  # - Linux 5.10 SLTS (EOL Jan 2031)
  # - Linux 5.15 LTS (EOL Dev 2026)
  def self.supported? : Bool
    return false unless System::IoUring.supported?

    System::IoUring.supports_feature?(LibC::IORING_FEAT_NODROP) &&
      System::IoUring.supports_feature?(LibC::IORING_FEAT_RW_CUR_POS) &&
      System::IoUring.supports_feature?(LibC::IORING_FEAT_EXT_ARG) &&
      System::IoUring.supports_opcode?(LibC::IORING_OP_OPENAT) &&
      System::IoUring.supports_opcode?(LibC::IORING_OP_READ) &&
      System::IoUring.supports_opcode?(LibC::IORING_OP_WRITE) &&
      System::IoUring.supports_opcode?(LibC::IORING_OP_CLOSE) &&
      System::IoUring.supports_opcode?(LibC::IORING_OP_CONNECT) &&
      System::IoUring.supports_opcode?(LibC::IORING_OP_ACCEPT) &&
      System::IoUring.supports_opcode?(LibC::IORING_OP_SEND) &&
      System::IoUring.supports_opcode?(LibC::IORING_OP_RECVMSG) &&
      System::IoUring.supports_opcode?(LibC::IORING_OP_SHUTDOWN) &&
      System::IoUring.supports_opcode?(LibC::IORING_OP_POLL_ADD) &&
      System::IoUring.supports_opcode?(LibC::IORING_OP_TIMEOUT) &&
      System::IoUring.supports_opcode?(LibC::IORING_OP_TIMEOUT_REMOVE) &&
      System::IoUring.supports_opcode?(LibC::IORING_OP_LINK_TIMEOUT) &&
      System::IoUring.supports_opcode?(LibC::IORING_OP_ASYNC_CANCEL) &&
      System::IoUring.supports_opcode?(LibC::IORING_OP_MSG_RING)
  end

  DEFAULT_SQ_ENTRIES = 16
  DEFAULT_CQ_ENTRIES = 128
  DEFAULT_SQ_THREAD_IDLE = 2000

  CLOSE_RING_EVENT = GC.malloc(sizeof(Event)).as(Event*)

  # SQPOLL without fixed files was added in Linux 5.11 with CAP_SYS_NICE
  # privilege and Linux 5.13 unprivileged.
  protected def self.create_ring(ring = nil)
    Ring.new(
      sq_entries: DEFAULT_SQ_ENTRIES,
      cq_entries: DEFAULT_CQ_ENTRIES,
      sq_thread_idle: (DEFAULT_SQ_THREAD_IDLE if System::IoUring.supports_feature?(LibC::IORING_FEAT_SQPOLL_NONFIXED)),
      wq_fd: ring.try(&.fd)
    )
  end

  @main_ring : Uring

  def initialize(parallelism : Int32)
    @main_ring = self.class.create_ring

    {% if flag?(:execution_context) %}
      @rings = Array(Ring?).new(parallelism)
      @rings << @main_ring
      @mutex = Thread::Mutex.new
    {% end %}
  end

  def after_fork_before_exec : Nil
    {% if flag?(:execution_context) %}
      @rings.each(&.close)
    {% else %}
      @main_ring.close
    {% end %}
  end

  {% unless flag?(:preview_mt) %}
    def after_fork : Nil
      # @main_ring.close
      # @main_ring = self.class.create_ring
    end
  {% end %}

  private def ring : Ring
    {% if flag?(:execution_context) %}
      Fiber::ExecutionContext::Scheduler.current.__evloop_ring
    {% else %}
      @main_ring
    {% end %}
  end

  private def ring? : Ring?
    {% if flag?(:execution_context) %}
      Fiber::ExecutionContext::Scheduler.current?.try(&.__evloop_ring)
    {% else %}
      @main_ring
    {% end %}
  end

  {% if flag?(:execution_context) %}
    def on_parallelism_change(parallelism : Int32)
      @mutex.synchronize do
        # can't shrink the rings' array: a ring may still have pending ops!
        return if parallelism <= @rings.parallelism

        # don't reallocate so a full evloop run can safely iterate without
        # having to lock the mutex
        rings = Array(Ring?).new(parallelism) { |index| @rings[index]? }

        # make sure that *rings* has been populated before we replace the
        # reference
        Atomic::Ops.store(pointerof(@rings), rings, :sequentially_consistent, volatile: false)
      end
    end

    def register(scheduler : Fiber::ExecutionContext::Scheduler, index : Int32) : Nil
      scheduler.__evloop_ring = @rings[index]
    end

    def unregister(scheduler : Fiber::ExecutionContext::Scheduler) : Nil
      return unless ring = scheduler.__evloop_ring?
      scheduler.__evloop_ring = nil

      # The ring might have operations pending, for example the parallel context
      # has been resized down and is shutting down schedulers, so we must delay
      # the actual close to after the ring's queue has been drained.
      ring.submit do |sqe|
        sqe.value.opcode = LibC::IORING_OP_NOP
        sqe.value.flags = LibC::IOSQE_IO_DRAIN
        sqe.value.user_data = CLOSE_RING_EVENT.address.to_u64!
      end
    end
  {% end %}

  def run(blocking : Bool) : Bool
    enqueued = false

    system_run(blocking) do |fiber|
      fiber.enqueue
      enqueued = true
    end

    enqueued
  end

  {% if flag?(:execution_context) %}
    def run(queue : Fiber::List*, blocking : Bool) : Bool
      system_run(blocking) { |fiber| queue.value.push(fiber) }
    end
  {% end %}

  private def system_run(blocking : Bool, & : Fiber ->) : Nil
    Crystal.trace :evloop, "run", blocking: blocking

    size = 0

    {% if flag?(:execution_context) %}
      rings = @rings

      if rings.size > 1 && (blocking || ring.once_in_a_while?)
        # when blocking or every once in a while (to check the rings of parked
        # or shutdown schedulers + avoid ready events being blocked by a busy
        # thread), we run a full scan of the rings; we iterate the rings from a
        # random entry to avoid having a bias on the first ones
        i = ring.@rng.rand(0...rings.size)

        rings.size.times do |j|
          next unless ring = rings[(i + j) % rings.size]
          # next if ring.empty?

          # try to lock the CQ ring, abort if already locked (another thread is
          # processing it)
          if ring.cq_trylock?
            process_cqes(ring) do |fiber|
              yield fiber
              size += 1
            end
          end

          # abort when an arbitrary amount of events has been processed so we
          # don't block the current thread for longer than necessary
          return if size >= 128
        end

        return unless size == 0
      end
    {% end %}

    # only process the local CQ ring
    ring = self.ring
    ring.cq_lock do
      # check CQEs (avoiding syscalls)
      process_cqes(ring) do |fiber|
        yield fiber
        size += 1
      end

      case size
      when 0
        # CQ was empty: ask and/or wait for completions
        ring.waiting do
          ring.enter(min_complete: blocking ? 1_u32 : 0_u32, flags: LibC::IORING_ENTER_GETEVENTS)
        end
      when ring.@cq_entries.value
        # CQ was full: tell kernel that it can report pending completions
        ring.enter(flags: LibC::IORING_ENTER_GETEVENTS)
      else
        return
      end

      process_cqes(ring) { |fiber| yield fiber }
    end
  end

  private def process_cqes(ring, &)
    size = 0

    ring.each_completed do |cqe|
      Ring.trace(cqe)

      # skip CQE without an Event
      next unless event = Pointer(Event).new(cqe.value.user_data)

      if event == CLOSE_RING_EVENT
        @mutex.synchronize do
          if index = @rings.index(ring)
            @rings[index] = nil
          end
        end
        ring.close
        return
      end

      fiber = event.value.fiber

      # TODO: shouldn't happen here (but in dedicated process cancelable timers block)
      if event.value.type.select_timeout?
        next unless select_action = fiber.timeout_select_action
        fiber.timeout_select_action = nil
        next unless select_action.time_expired?
        fiber.@timeout_event.as(FiberEvent).clear
      end

      event.value.res = cqe.value.res
      # event.value.flags = cqe.value.flags

      yield fiber
    end
  end

  def interrupt : Nil
    return unless waiting_ring = @rings.find_by(&.try(&.waiting?))

    # we might interrupt from a raw thread, with no scheduler nor evloop
    ring = ring? || waiting_ring

    ring.submit do |sqe|
      sqe.value.opcode = LibC::IORING_OP_MSG_RING
      sqe.value.fd = waiting_ring.fd
    end
  end

  # timers

  # TODO: store cancelable timers in `Crystal::Timers`, wait until next ready
  # timeout on blocking evloop runs; process ready timers on evloop runs (skip
  # if already processing).

  def add_timer(event : Event*) : Nil
    ring.submit do |sqe|
      sqe.value.opcode = LibC::IORING_OP_TIMEOUT
      sqe.value.user_data = event.address.to_u64!
      sqe.value.addr = event.value.timespec.address.to_u64!
      sqe.value.len = 1
    end
  end

  def delete_timer(event : Event*) : Nil
    ring.submit do |sqe|
      sqe.value.opcode = LibC::IORING_OP_TIMEOUT_REMOVE
      sqe.value.addr = event.address.to_u64!
    end
  end

  # fiber interface, see Crystal::EventLoop

  def sleep(duration : Time::Span) : Nil
    async_impl(type) do |event|
      event.value.timeout = duration

      ring.submit do |sqe|
        sqe.value.opcode = LibC::IORING_OP_TIMEOUT
        sqe.value.user_data = event.address.to_u64!
        sqe.value.addr = event.value.timespec.address.to_u64!
        sqe.value.len = 1
      end
    end
  end

  def create_timeout_event(fiber : Fiber) : FiberEvent
    FiberEvent.new(:select_timeout, fiber)
  end

  # file descriptor interface, see Crystal::EventLoop::FileDescriptor

  def pipe(read_blocking : Bool?, write_blocking : Bool?) : {IO::FileDescriptor, IO::FileDescriptor}
    r, w = System::FileDescriptor.system_pipe
    System::FileDescriptor.set_blocking(r, false) if read_blocking == false
    System::FileDescriptor.set_blocking(w, false) if write_blocking == false
    {
      IO::FileDescriptor.new(handle: r),
      IO::FileDescriptor.new(handle: w),
    }
  end

  def open(path : String, flags : Int32, permissions : File::Permissions, blocking : Bool?) : {System::FileDescriptor::Handle, Bool} | Errno
    path.check_no_null_byte

    fd = ring.async(LibC::IORING_OP_OPENAT) do |sqe|
      sqe.value.fd = LibC::AT_FDCWD
      sqe.value.addr = path.to_unsafe.address.to_u64!
      sqe.value.sflags.open_flags = flags | LibC::O_CLOEXEC
      sqe.value.len = permissions
    end
    return Errno.new(-fd) if fd < 0

    blocking = true if blocking.nil?
    System::FileDescriptor.set_blocking(fd, false) if blocking
    {fd, blocking}
  end

  def read(file_descriptor : System::FileDescriptor, slice : Bytes) : Int32
    async_rw(LibC::IORING_OP_READ, file_descriptor, slice, file_descriptor.@read_timeout) do |errno|
      case errno
      when Errno::ECANCELED
        raise IO::TimeoutError.new("Read timed out")
      when Errno::EBADF
        raise IO::Error.new("File not open for reading", target: file_descriptor)
      else
        raise IO::Error.from_os_error("read", errno, target: file_descriptor)
      end
    end
  end

  def wait_readable(file_descriptor : System::FileDescriptor) : Nil
    async_poll(file_descriptor, LibC::POLLIN | LibC::POLLRDHUP, file_descriptor.@read_timeout) { "Read timed out" }
  end

  def write(file_descriptor : System::FileDescriptor, slice : Bytes) : Int32
    async_rw(LibC::IORING_OP_WRITE, file_descriptor, slice, file_descriptor.@write_timeout) do |errno|
      case errno
      when Errno::ECANCELED
        raise IO::TimeoutError.new("Write timed out")
      when Errno::EBADF
        raise IO::Error.new("File not open for writing", target: file_descriptor)
      else
        raise IO::Error.from_os_error("write", errno, target: file_descriptor)
      end
    end
  end

  def wait_writable(file_descriptor : System::FileDescriptor) : Nil
    async_poll(file_descriptor, LibC::POLLOUT, file_descriptor.@write_timeout) { "Write timed out" }
  end

  def reopened(file_descriptor : System::FileDescriptor) : Nil
    # nothing to do
  end

  def close(file_descriptor : System::FileDescriptor) : Nil
    # sync with `FileDescriptor#file_descriptor_close`: prevent actual close
    return unless fd = file_descriptor.close_volatile_fd?

    # FIXME: we must submit an IORING_OP_ASYNC_CANCEL to every ring (across
    # execution contexts) that has a pending READ/WRITE/POLL operation on the
    # IO::FileDescriptor; we can't just link CANCEL to CLOSE on the local
    # ring...

    async_close(fd) do |sqe|
      # one thread closing a fd won't interrupt reads or writes happening in
      # other threads, for example a blocked read on a fifo will keep blocking,
      # while close would have finished and closed the fd; we thus explicitly
      # cancel any pending operations on the fd before we try to close
      sqe.value.opcode = LibC::IORING_OP_ASYNC_CANCEL
      sqe.value.sflags.cancel_flags = LibC::IORING_ASYNC_CANCEL_FD
      sqe.value.fd = fd
    end
  end

  # socket interface, see Crystal::EventLoop::Socket

  def socket(family : ::Socket::Family, type : ::Socket::Type, protocol : ::Socket::Protocol, blocking : Bool?) : {::Socket::Handle, Bool}
    blocking = true if blocking.nil?
    socket = System::Socket.socket(family, type, protocol, blocking)
    {socket, blocking}
  end

  def socketpair(type : ::Socket::Type, protocol : ::Socket::Protocol) : Tuple({::Socket::Handle, ::Socket::Handle}, Bool)
    socket = System::Socket.socketpair(type, protocol, blocking: true)
    {socket, true}
  end

  def read(socket : ::Socket, slice : Bytes) : Int32
    async_rw(LibC::IORING_OP_READ, socket, slice, socket.@read_timeout) do |errno|
      case errno
      when Errno::ECANCELED
        raise IO::TimeoutError.new("Read timed out")
      else
        raise IO::Error.from_os_error("read", errno, target: socket)
      end
    end
  end

  def wait_readable(socket : ::Socket) : Nil
    async_poll(socket, LibC::POLLIN | LibC::POLLRDHUP, socket.@read_timeout) { "Read timed out" }
  end

  def write(socket : ::Socket, slice : Bytes) : Int32
    async_rw(LibC::IORING_OP_WRITE, socket, slice, socket.@write_timeout) do |errno|
      case errno
      when Errno::ECANCELED
        raise IO::TimeoutError.new("Write timed out")
      else
        raise IO::Error.from_os_error("write", errno, target: socket)
      end
    end
  end

  def wait_writable(socket : ::Socket) : Nil
    async_poll(socket, LibC::POLLOUT, socket.@write_timeout) { "Write timed out" }
  end

  def accept(socket : ::Socket) : {::Socket::Handle, Bool}?
    ret = ring.async(LibC::IORING_OP_ACCEPT, socket.@read_timeout) do |sqe|
      sqe.value.fd = socket.fd
      sqe.value.sflags.accept_flags = LibC::SOCK_CLOEXEC
    end
    return {ret, true} unless ret < 0

    if ret == -LibC::ECANCELED
      raise IO::TimeoutError.new("Accept timed out")
    elsif !socket.closed?
      raise ::Socket::Error.from_os_error("accept", Errno.new(-ret))
    end
  end

  def connect(socket : ::Socket, address : ::Socket::Addrinfo | ::Socket::Address, timeout : Time::Span?) : IO::Error?
    sockaddr = address.to_unsafe # OPTIMIZE: #to_unsafe allocates (not needed)
    addrlen = address.size

    ret = ring.async(LibC::IORING_OP_CONNECT, timeout) do |sqe|
      sqe.value.fd = socket.fd
      sqe.value.addr = sockaddr.address.to_u64!
      sqe.value.u1.off = addrlen.to_u64!
    end
    return if ret == 0

    if ret == -LibC::ECANCELED
      IO::TimeoutError.new("Connect timed out")
    elsif ret != -LibC::EISCONN
      ::Socket::ConnectError.from_os_error("connect", Errno.new(-ret))
    end
  end

  # TODO: support socket.@write_timeout (?)
  def send_to(socket : ::Socket, slice : Bytes, address : ::Socket::Address) : Int32
    sockaddr = address.to_unsafe # OPTIMIZE: #to_unsafe allocates (not needed)
    addrlen = address.size

    res = ring.async(LibC::IORING_OP_SEND) do |sqe|
      sqe.value.fd = socket.fd
      sqe.value.addr = slice.to_unsafe.address.to_u64!
      sqe.value.len = slice.size.to_u64!
      sqe.value.u1.addr2 = sockaddr.address.to_u64!
      sqe.value.addr_len[0] = addrlen.to_u16!
    end

    if res == 0
      check_open(socket)
    elsif res < 0
      raise ::Socket::Error.from_os_error("Error sending datagram to #{address}", Errno.new(-res))
    end

    res
  end

  # TODO: support socket.@read_timeout (?)
  def receive_from(socket : ::Socket, slice : Bytes) : {Int32, ::Socket::Address}
    sockaddr = LibC::SockaddrStorage.new
    sockaddr.ss_family = socket.family
    addrlen = LibC::SocklenT.new(sizeof(LibC::SockaddrStorage))

    # as of linux 6.12 there is no IORING_OP_RECVFROM
    iovec = LibC::Iovec.new(iov_base: slice.to_unsafe, iov_len: slice.size)
    msghdr = LibC::Msghdr.new(msg_name: pointerof(sockaddr), msg_namelen: addrlen, msg_iov: pointerof(iovec), msg_iovlen: 1)

    res = ring.async(LibC::IORING_OP_RECVMSG) do |sqe|
      sqe.value.fd = socket.fd
      sqe.value.addr = pointerof(msghdr).address.to_u64!
    end

    if res == 0
      check_open(socket)
    elsif res < 0
      raise IO::Error.from_os_error("recvfrom", Errno.new(-res), target: socket)
    end

    {res, ::Socket::Address.from(pointerof(sockaddr).as(LibC::Sockaddr*), msghdr.msg_namelen)}
  end

  def close(socket : ::Socket) : Nil
    # sync with `Socket#socket_close`
    return unless fd = socket.close_volatile_fd?

    # we must shutdown a socket before closing it, otherwise a pending accept
    # or read won't be interrupted for example;
    async_close(fd) do |sqe|
      sqe.value.opcode = LibC::IORING_OP_SHUTDOWN
      sqe.value.fd = fd
      sqe.value.len = LibC::SHUT_RDWR
    end
  end

  # internals

  private def check_open(io)
    raise IO::Error.new("Closed stream") if io.closed?
  end

  private def async_rw(opcode, io, slice, timeout, &)
    loop do
      res = ring.async(opcode, timeout) do |sqe|
        sqe.value.fd = io.fd
        sqe.value.u1.off = -1
        sqe.value.addr = slice.to_unsafe.address.to_u64!
        sqe.value.len = slice.size
      end
      return res if res >= 0

      check_open(io)
      yield Errno.new(-res) unless res == -LibC::EINTR
    end
  end

  private def async_poll(io, poll_events, timeout, &)
    res = ring.async(LibC::IORING_OP_POLL_ADD, timeout) do |sqe|
      sqe.value.fd = io.fd
      sqe.value.sflags.poll_events = poll_events | LibC::POLLERR | LibC::POLLHUP
    end
    check_open(io)
    raise IO::TimeoutError.new(yield) if res == -LibC::ECANCELED
  end

  private def async_close(fd, &)
    sqes = uninitialized Pointer(LibC::IoUringSqe)[2]

    res = async_impl do |event|
      ring.submit(sqes.to_slice) do
        # linux won't interrupt pending operations on a file descriptor when it
        # closes it, we thus first create an operation to cancel any pending
        # operations; we don't attach that cancel operation to an event: handling
        # the CQE for close is enough
        sqes[0].value.flags = LibC::IOSQE_IO_LINK | LibC::IOSQE_IO_HARDLINK
        yield sqes[0]

        # then we setup the close operation
        sqes[1].value.opcode = LibC::IORING_OP_CLOSE
        sqes[1].value.user_data = event.address.to_u64!
        sqes[1].value.fd = fd
      end
    end

    case res
    when 0
      # success
    when -LibC::EINTR, -LibC::EINPROGRESS
      # ignore
    else
      raise IO::Error.from_os_error("Error closing file", Errno.new(-res))
    end
  end

  private def async(opcode, link_timeout = nil, &)
    sqes = uninitialized Pointer(LibC::IoUringSqe)[2]

    async_impl do |event|
      count = link_timeout ? 2 : 1

      ring.submit(sqes.to_slice[0, count]) do
        sqes[0].value.opcode = opcode
        sqes[0].value.event = event.address.to_u64!
        yield sqes[0]

        if link_timeout
          event.value.timeout = link_timeout

          # chain the operations
          sqes[0].value.flags = op_sqe.value.flags | LibC::IOSQE_IO_LINK

          # configure the timeout operation
          sqes[1] = unsafe_next_sqe
          sqes[1].value.opcode = LibC::IORING_OP_LINK_TIMEOUT
          sqes[1].value.addr = event.value.timespec.address.to_u64!
          sqes[1].value.len = 1
        end
      end
    end
  end

  private def async_impl(type = Event::Type::Async, &)
    event = Event.new(type, Fiber.current)
    yield pointerof(event)
    Fiber.suspend
    event.res
  end
end
