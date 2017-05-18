require "./stddef"
require "./sys/wait"

lib LibC
  struct DivT
    quot : Int
    rem : Int
  end

  fun atof(nptr : Char*) : Double
  fun div(numer : Int, denom : Int) : DivT
  fun exit(status : Int) : NoReturn
  fun free(x0 : Void*) : Void
  fun getenv(string : Char*) : Char*
  fun malloc(size : SizeT) : Void*
  fun mkstemp(x0 : Char*) : Int
  fun putenv(string : Char*) : Int
  fun realloc(r : Void*, size : SizeT) : Void*
  fun realpath(path : Char*, resolved_path : Char*) : Char*
  fun setenv(string : Char*, value : Char*, overwrite : Int) : Int
  fun strtod(n : Char*, end_PTR : Char**) : Double
  fun strtof(n : Char*, end_PTR : Char**) : Float
  fun strtol(n : Char*, end_PTR : Char**, base : Int) : Long
  fun unsetenv(x0 : Char*) : Int
end
