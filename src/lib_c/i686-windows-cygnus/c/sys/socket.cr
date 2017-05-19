require "./types"

lib LibC
  SOCK_DGRAM     =      2
  SOCK_RAW       =      3
  SOCK_SEQPACKET =      5
  SOCK_STREAM    =      1
  SOL_SOCKET     = 0xffff
  SO_BROADCAST   = 0x0020
  SO_KEEPALIVE   = 0x0008
  SO_LINGER      = 0x0080
  SO_RCVBUF      = 0x1002
  SO_REUSEADDR   = 0x0004
  SO_SNDBUF      = 0x1001
  PF_INET        = LibC::AF_INET
  PF_INET6       = LibC::AF_INET6
  PF_UNIX        = LibC::AF_UNIX
  PF_UNSPEC      = LibC::AF_UNSPEC
  PF_LOCAL       = LibC::AF_LOCAL
  AF_INET        =          2
  AF_INET6       =         23
  AF_UNIX        =          1
  AF_UNSPEC      =          0
  AF_LOCAL       =          1
  SHUT_RD        =          0
  SHUT_RDWR      =          2
  SHUT_WR        =          1
  SOCK_CLOEXEC   = 0x02000000

  alias SocklenT = Int
  alias SaFamilyT = UInt16T

  struct Sockaddr
    sa_family : SaFamilyT
    sa_data : StaticArray(Char, 14)
  end

  struct SockaddrStorage
    ss_family : SaFamilyT
    _ss_pad1 : StaticArray(Char, 6)
    __ss_align : Int64T
    _ss_pad2 : StaticArray(Char, 112)
  end

  struct Linger
    l_onoff : UShort
    l_linger : UShort
  end

  fun accept(x0 : Int, peer : Sockaddr*, x2 : SocklenT*) : Int
  fun bind(x0 : Int, my_addr : Sockaddr*, addrlen : SocklenT) : Int
  fun connect(x0 : Int, x1 : Sockaddr*, x2 : SocklenT) : Int
  fun getpeername(x0 : Int, peer : Sockaddr*, x2 : SocklenT*) : Int
  fun getsockname(x0 : Int, addr : Sockaddr*, x2 : SocklenT*) : Int
  fun getsockopt(s : Int, level : Int, optname : Int, optval : Void*, optlen : SocklenT*) : Int
  fun listen(x0 : Int, n : Int) : Int
  fun recv(x0 : Int, buff : Void*, len : SizeT, flags : Int) : SSizeT
  fun recvfrom(x0 : Int, buff : Void*, len : SizeT, flags : Int, from : Sockaddr*, fromlen : SocklenT*) : SSizeT
  fun send(x0 : Int, buff : Void*, len : SizeT, flags : Int) : SSizeT
  fun sendto(x0 : Int, x1 : Void*, len : SizeT, flags : Int, to : Sockaddr*, tolen : SocklenT) : SSizeT
  fun setsockopt(s : Int, level : Int, optname : Int, optval : Void*, optlen : SocklenT) : Int
  fun shutdown(x0 : Int, x1 : Int) : Int
  fun socket(family : Int, type : Int, protocol : Int) : Int
  fun socketpair(domain : Int, type : Int, protocol : Int, socket_vec : Int*) : Int
end
