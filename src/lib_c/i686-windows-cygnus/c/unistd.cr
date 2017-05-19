require "./sys/types"
require "./stdint"

lib LibC
  F_OK       = 0
  R_OK       = 4
  W_OK       = 2
  X_OK       = 1
  SC_CLK_TCK = 2

  fun access(path : Char*, amode : Int) : Int
  fun chdir(path : Char*) : Int
  fun chown(path : Char*, owner : UidT, group : GidT) : Int
  fun close(fildes : Int) : Int
  fun dup2(fildes : Int, fildes2 : Int) : Int
  fun _exit(status : Int) : NoReturn
  fun execvp(file : Char*, argv : Char**) : Int
  @[ReturnsTwice]
  fun fork : PidT
  fun ftruncate(fd : Int, length : OffT) : Int
  fun getcwd(buf : Char*, size : SizeT) : Char*
  fun gethostname(name : Char*, len : SizeT) : Int
  fun getpgid(x0 : PidT) : PidT
  fun getpid : PidT
  fun getppid : PidT
  fun isatty(fildes : Int) : Int
  fun lchown(path : Char*, owner : UidT, group : GidT) : Int
  fun link(path1 : Char*, path2 : Char*) : Int
  fun lockf(fd : Int, cmd : Int, len : OffT) : Int
  fun lseek(fildes : Int, offset : OffT, whence : Int) : OffT
  fun pipe(fildes : StaticArray(Int, 2)) : Int
  fun pread(fd : Int, buf : Void*, nbyte : SizeT, off : OffT) : SSizeT
  fun pwrite(fd : Int, buf : Void*, nbyte : SizeT, off : OffT) : SSizeT
  fun read(fd : Int, buf : Void*, nbyte : SizeT) : SSizeT
  fun rmdir(path : Char*) : Int
  fun symlink(name1 : Char*, name2 : Char*) : Int
  fun sysconf(name : Int) : Long
  fun unlink(path : Char*) : Int
  fun write(fd : Int, buf : Void*, nbyte : SizeT) : SSizeT
end
