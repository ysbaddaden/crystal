lib LibC
  fun abort : NoReturn
  fun exit(status : Int32) : NoReturn
  fun puts(string : UInt8*) : Int32
  fun strcmp(left : UInt8*, right : UInt8*) : Int32
end
