require "./sys/types"

lib LibC
  type DIR = Void

  struct Dirent
    __d_version : UInt32T
    d_ino : InoT
    d_type : Char
    __d_unused1 : StaticArray(Char, 3)
    __d_internal1 : UInt32T
    d_name : StaticArray(Char, 256)
  end

  fun closedir(x0 : DIR*) : Int
  fun opendir(x0 : Char*) : DIR*
  fun readdir(x0 : DIR*) : Dirent*
  fun rewinddir(x0 : DIR*) : Void
end
