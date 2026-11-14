require "c/netdb"
require "c/netinet/tcp"
require "c/sys/socket"

module Crystal::System::Socket
  alias Handle = Int32

  private def initialize_handle(fd, blocking = nil)
  end

  private def system_bind(addr : ::Socket::UNIXAddress, addrstr)
    raise NotImplementedError.new("WASI does not support UNIX sockets")
  end

  private def system_bind(addr, addrstr)
    {% if flag?(:wasip1) %}
      raise NotImplementedError.new("Crystal::System::Socket#system_bind requires wasip2 or later")
    {% else %}
      unless LibC.bind(fd, addr, addr.size) == 0
        ::Socket::BindError.from_errno("Could not bind to '#{addrstr}'")
      end
    {% end %}
  end

  private def system_listen(backlog)
    {% if flag?(:wasip1) %}
      raise NotImplementedError.new("Crystal::System::Socket#system_listen requires wasip2 or later")
    {% else %}
      unless LibC.listen(fd, backlog) == 0
        ::Socket::Error.from_errno("Listen failed")
      end
    {% end %}
  end

  private def system_close_read
    if LibC.shutdown(fd, LibC::SHUT_RD) != 0
      raise ::Socket::Error.from_errno("shutdown read")
    end
  end

  private def system_close_write
    if LibC.shutdown(fd, LibC::SHUT_WR) != 0
      raise ::Socket::Error.from_errno("shutdown write")
    end
  end

  private def system_accept : {::Socket::Handle, Bool}?
    event_loop.accept(self)
  end

  private def system_send_buffer_size : Int
    {% if flag?(:wasip1) %}
      raise NotImplementedError.new("Crystal::System::Socket#system_send_buffer_size requires wasip2 or later")
    {% else %}
      getsockopt LibC::SO_SNDBUF, 0
    {% end %}
  end

  private def system_send_buffer_size=(val : Int)
    {% if flag?(:wasip1) %}
      raise NotImplementedError.new("Crystal::System::Socket#system_send_buffer_size= requires wasip2 or later")
    {% else %}
      setsockopt LibC::SO_SNDBUF, val
    {% end %}
  end

  private def system_recv_buffer_size : Int
    {% if flag?(:wasip1) %}
      raise NotImplementedError.new("Crystal::System::Socket#system_recv_buffer_size requires wasip2 or later")
    {% else %}
      getsockopt LibC::SO_RCVBUF, 0
    {% end %}
  end

  private def system_recv_buffer_size=(val : Int)
    {% if flag?(:wasip1) %}
      raise NotImplementedError.new("Crystal::System::Socket#system_recv_buffer_size= requires wasip2 or later")
    {% else %}
      setsockopt LibC::SO_RCVBUF, val
    {% end %}
  end

  private def system_reuse_address? : Bool
    {% if flag?(:wasip1) %}
      raise NotImplementedError.new("Crystal::System::Socket#system_reuse_address? requires wasip2 or later")
    {% else %}
      getsockopt_bool LibC::SO_REUSEADDR
    {% end %}
  end

  private def system_reuse_address=(val : Bool)
    {% if flag?(:wasip1) %}
      raise NotImplementedError.new("Crystal::System::Socket#system_reuse_address= requires wasip2 or later")
    {% else %}
      setsockopt_bool LibC::SO_REUSEADDR, val
    {% end %}
  end

  private def system_reuse_port?
    false
  end

  private def system_reuse_port=(val : Bool)
    raise NotImplementedError.new "Crystal::System::Socket#system_reuse_port=" if val
  end

  private def system_broadcast? : Bool
    false
  end

  private def system_broadcast=(val : Bool)
    raise NotImplementedError.new "Crystal::System::Socket#system_broadcast=" if val
  end

  private def system_keepalive? : Bool
    {% if flag?(:wasip1) %}
      raise NotImplementedError.new("Crystal::System::Socket#system_keepalive? requires wasip2 or later")
    {% else %}
      getsockopt_bool LibC::SO_KEEPALIVE
    {% end %}
  end

  private def system_keepalive=(val : Bool)
    {% if flag?(:wasip1) %}
      raise NotImplementedError.new("Crystal::System::Socket#system_keepalive= requires wasip2 or later")
    {% else %}
      setsockopt_bool LibC::SO_KEEPALIVE, val
    {% end %}
  end

  private def system_linger
    false
  end

  private def system_linger=(val)
    raise NotImplementedError.new "Crystal::System::Socket#system_linger=" if val
  end

  private def system_getsockopt(optname, optval, level = LibC::SOL_SOCKET, &)
    {% if flag?(:wasip1) %}
      raise NotImplementedError.new("Crystal::System::Socket#system_getsockopt requires wasip2 or later")
    {% else %}
      optsize = LibC::SocklenT.new(sizeof(typeof(optval)))
      ret = LibC.getsockopt(fd, level, optname, pointerof(optval), pointerof(optsize))
      yield optval if ret == 0
      ret
    {% end %}
  end

  private def system_getsockopt(optname, optval, level = LibC::SOL_SOCKET)
    {% if flag?(:wasip1) %}
      raise NotImplementedError.new("Crystal::System::Socket#system_getsockopt requires wasip2 or later")
    {% else %}
      system_getsockopt(optname, optval, level) { |value| return value }
      raise ::Socket::Error.from_errno("getsockopt #{optname}")
    {% end %}
  end

  private def system_setsockopt(optname, optval, level = LibC::SOL_SOCKET)
    {% if flag?(:wasip1) %}
      raise NotImplementedError.new("Crystal::System::Socket#system_setsockopt requires wasip2 or later")
    {% else %}
      optsize = LibC::SocklenT.new(sizeof(typeof(optval)))
      ret = LibC.setsockopt(fd, level, optname, pointerof(optval), optsize)
      raise ::Socket::Error.from_errno("setsockopt #{optname}") if ret == -1
      ret
    {% end %}
  end

  private def system_blocking?
    Socket.get_blocking(fd)
  end

  private def system_blocking=(value)
    Socket.set_blocking(fd, value)
  end

  def self.get_blocking(fd : Handle)
    fcntl(fd, LibC::F_GETFL) & LibC::O_NONBLOCK == 0
  end

  def self.set_blocking(fd : Handle, value : Bool)
    flags = fcntl(fd, LibC::F_GETFL)
    if value
      flags &= ~LibC::O_NONBLOCK
    else
      flags |= LibC::O_NONBLOCK
    end
    fcntl(fd, LibC::F_SETFL, flags)
  end

  private def system_close_on_exec?
    flags = Socket.fcntl(fd, LibC::F_GETFD)
    (flags & LibC::FD_CLOEXEC) == LibC::FD_CLOEXEC
  end

  private def system_close_on_exec=(arg : Bool)
    Socket.fcntl(fd, LibC::F_SETFD, arg ? LibC::FD_CLOEXEC : 0)
    arg
  end

  def self.fcntl(fd, cmd, arg = 0)
    r = LibC.fcntl fd, cmd, arg
    raise ::Socket::Error.from_errno("fcntl() failed") if r == -1
    r
  end

  private def system_fcntl(cmd, arg = 0)
    Socket.fcntl(fd, cmd, arg)
  end

  private def system_tty?
    LibC.isatty(fd) == 1
  end

  def socket_close
    # Clear the @volatile_fd before actually closing it in order to
    # reduce the chance of reading an outdated fd value
    return unless fd = close_volatile_fd?

    ret = LibC.close(fd)

    if ret != 0
      case Errno.value
      when Errno::EINTR, Errno::EINPROGRESS
        # ignore
      else
        raise ::Socket::Error.from_errno("Error closing socket")
      end
    end
  end

  def close_volatile_fd? : Int32?
    fd = @volatile_fd.swap(-1)
    fd unless fd == -1
  end

  private def system_local_address : ::Socket::IPAddress
    {% if flag?(:wasip1) %}
      raise NotImplementedError.new("Crystal::System::Socket#system_local_address requires wasip2 or later")
    {% else %}
      sockaddr6 = uninitialized LibC::SockaddrIn6
      sockaddr = pointerof(sockaddr6).as(LibC::Sockaddr*)
      addrlen = sizeof(LibC::SockaddrIn6).to_u32!

      if LibC.getsockname(fd, sockaddr, pointerof(addrlen)) != 0
        raise ::Socket::Error.from_errno("getsockname")
      end

      ::Socket::IPAddress.from(sockaddr, addrlen)
    {% end %}
  end

  private def system_remote_address : ::Socket::IPAddress
    {% if flag?(:wasip1) %}
      raise NotImplementedError.new("Crystal::System::Socket#system_remote_address requires wasip2 or later")
    {% else %}
      sockaddr6 = uninitialized LibC::SockaddrIn6
      sockaddr = pointerof(sockaddr6).as(LibC::Sockaddr*)
      addrlen = sizeof(LibC::SockaddrIn6).to_u32!

      if LibC.getpeername(fd, sockaddr, pointerof(addrlen)) != 0
        raise ::Socket::Error.from_errno("getpeername")
      end

      ::Socket::IPAddress.from(sockaddr, addrlen)
    {% end %}
  end

  private def system_tcp_keepalive_idle
    getsockopt LibC::TCP_KEEPIDLE, 0, level: ::Socket::Protocol::TCP
  end

  private def system_tcp_keepalive_idle=(val : Int)
    setsockopt LibC::TCP_KEEPIDLE, val, level: ::Socket::Protocol::TCP
    val
  end

  private def system_tcp_keepalive_interval
    getsockopt LibC::TCP_KEEPINTVL, 0, level: ::Socket::Protocol::TCP
  end

  private def system_tcp_keepalive_interval=(val : Int)
    setsockopt LibC::TCP_KEEPINTVL, val, level: ::Socket::Protocol::TCP
    val
  end

  private def system_tcp_keepalive_count
    getsockopt LibC::TCP_KEEPCNT, 0, level: ::Socket::Protocol::TCP
  end

  private def system_tcp_keepalive_count=(val : Int)
    setsockopt LibC::TCP_KEEPCNT, val, level: ::Socket::Protocol::TCP
    val
  end

  private def system_sendfile(file : IO::FileDescriptor, offset : Int64, count : Int64) : Int64
    case result = event_loop.sendfile(self, file.fd, offset, count, 0)
    when Int64
      result
    else
      if result == Errno::ETIMEDOUT
        raise IO::TimeoutError.new("Sendfile timed out", target: self)
      end
      raise IO::Error.from_os_error("sendfile", result, target: self)
    end
  end

  def self.network_interface_to_index(name : String, & : WasiError ->) : Int
    raise NotImplementedError.new("Crystal::System::Socket.network_interface_to_index")
  end

  def self.network_interface_from_index(index : Int, & : WasiError ->) : String
    raise NotImplementedError.new("Crystal::System::Socket.network_interface_from_index")
  end
end
