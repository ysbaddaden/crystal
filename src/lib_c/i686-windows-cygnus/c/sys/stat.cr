require "./types"
require "../time"

lib LibC
  S_IFMT   = 0o170000
  S_IFBLK  = 0o060000
  S_IFCHR  = 0o020000
  S_IFIFO  = 0o010000
  S_IFREG  = 0o100000
  S_IFDIR  = 0o040000
  S_IFLNK  = 0o120000
  S_IFSOCK = 0o140000
  S_IRUSR  = 0o000400
  S_IWUSR  = 0o000200
  S_IXUSR  = 0o000100
  S_IRWXU  = S_IRUSR | S_IWUSR | S_IXUSR
  S_IRGRP  = 0o000040
  S_IWGRP  = 0o000020
  S_IXGRP  = 0o000010
  S_IRWXG  = S_IRGRP | S_IWGRP | S_IXGRP
  S_IROTH  = 0o000004
  S_IWOTH  = 0o000002
  S_IXOTH  = 0o000001
  S_IRWXO  = S_IROTH | S_IWOTH | S_IXOTH
  S_ISUID  = 0o004000
  S_ISGID  = 0o002000
  S_ISVTX  = 0o001000

  struct Stat
    st_dev : DevT
    st_ino : InoT
    st_mode : ModeT
    st_nlink : NlinkT
    st_uid : UidT
    st_gid : GidT
    st_rdev : DevT
    st_size : OffT
    st_atim : Timespec
    st_mtim : Timespec
    st_ctim : Timespec
    st_blksize : BlksizeT
    st_blocks : BlkcntT
    st_birthtim : Timespec
    __pad : StaticArray(UInt8, 12)
  end

  fun chmod(path : Char*, mode : ModeT) : Int
  fun fstat(fd : Int, sbuf : Stat*) : Int
  fun lstat(path : Char*, buf : Stat*) : Int
  fun mkdir(path : Char*, mode : ModeT) : Int
  fun mkfifo(path : Char*, mode : ModeT) : Int
  fun mknod(path : Char*, mode : ModeT, dev : DevT) : Int
  fun stat(path : Char*, sbuf : Stat*) : Int
  fun umask(mask : ModeT) : ModeT
end
