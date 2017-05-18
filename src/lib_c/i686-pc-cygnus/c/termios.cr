require "./sys/types"

lib LibC
  VEOF      =       4
  VEOL      =       2
  VERASE    =       5
  VINTR     =       6
  VKILL     =       7
  VMIN      =       9
  VQUIT     =      10
  VSTART    =      12
  VSTOP     =      13
  VSUSP     =      14
  BRKINT    = 0x00002
  ICRNL     = 0x00100
  IGNBRK    = 0x00001
  IGNCR     = 0x00080
  IGNPAR    = 0x00004
  INLCR     = 0x00040
  INPCK     = 0x00010
  ISTRIP    = 0x00020
  IXANY     = 0x08000
  IXOFF     = 0x01000
  IXON      = 0x00400
  PARMRK    = 0x10000
  OPOST     = 0x00001
  ONLCR     = 0x00008
  OCRNL     = 0x00004
  ONOCR     = 0x00010
  ONLRET    = 0x00020
  OFDEL     = 0x08000
  OFILL     = 0x00040
  CRDLY     = 0x00180
  CR0       = 0x00000
  CR1       = 0x00080
  CR2       = 0x00100
  CR3       = 0x00180
  TABDLY    = 0x01800
  TAB0      = 0x00000
  TAB1      = 0x00800
  TAB2      = 0x01000
  TAB3      = 0x01800
  BSDLY     = 0x00400
  BS0       = 0x00000
  BS1       = 0x00400
  VTDLY     = 0x02000
  VT0       = 0x00000
  VT1       = 0x02000
  FFDLY     = 0x04000
  FF0       = 0x00000
  FF1       = 0x04000
  NLDLY     = 0x00200
  NL0       = 0x00000
  NL1       = 0x00200
  B0        = 0x00000
  B50       = 0x00001
  B75       = 0x00002
  B110      = 0x00003
  B134      = 0x00004
  B150      = 0x00005
  B200      = 0x00006
  B300      = 0x00007
  B600      = 0x00008
  B1200     = 0x00009
  B1800     = 0x0000a
  B2400     = 0x0000b
  B4800     = 0x0000c
  B9600     = 0x0000d
  B19200    = 0x0000e
  B38400    = 0x0000f
  CSIZE     = 0x00030
  CS5       = 0x00000
  CS6       = 0x00010
  CS7       = 0x00020
  CS8       = 0x00030
  CSTOPB    = 0x00040
  CREAD     = 0x00080
  PARENB    = 0x00100
  PARODD    = 0x00200
  HUPCL     = 0x00400
  CLOCAL    = 0x00800
  ECHO      =  0x0004
  ECHOE     =  0x0008
  ECHOK     =  0x0010
  ECHONL    =  0x0020
  ICANON    =  0x0002
  IEXTEN    =  0x0100
  ISIG      =  0x0001
  NOFLSH    =  0x0040
  TOSTOP    =  0x0080
  TCSANOW   =       2
  TCSADRAIN =       3
  TCSAFLUSH =       1
  TCIFLUSH  =       0
  TCIOFLUSH =       2
  TCOFLUSH  =       1
  TCIOFF    =       2
  TCION     =       3
  TCOOFF    =       0
  TCOON     =       1

  alias CcT = Char
  alias SpeedT = UInt
  alias TcflagT = UInt

  struct Termios
    c_iflag : TcflagT
    c_oflag : TcflagT
    c_cflag : TcflagT
    c_lflag : TcflagT
    c_line : Char
    c_cc : StaticArray(CcT, 18)
    c_ispeed : SpeedT
    c_ospeed : SpeedT
  end

  fun tcgetattr(x0 : Int, x1 : Termios*) : Int
  fun tcsetattr(x0 : Int, x1 : Int, x2 : Termios*) : Int
  fun cfmakeraw(x0 : Termios*) : Void
end
