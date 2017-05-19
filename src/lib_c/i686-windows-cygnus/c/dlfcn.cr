lib LibC
  RTLD_LAZY    = 1
  RTLD_NOW     = 2
  RTLD_GLOBAL  = 4
  RTLD_LOCAL   = 0
  RTLD_DEFAULT = LibC::NULL

  fun dlclose(x0 : Void*) : Int
  fun dlerror : Char*
  fun dlopen(x0 : Char*, x1 : Int) : Void*
  fun dlsym(x0 : Void*, x1 : Char*) : Void*
end
