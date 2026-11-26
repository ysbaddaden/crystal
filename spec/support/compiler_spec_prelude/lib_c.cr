lib LibC
  {% if flag?(:bits64) %}
    alias SizeT = UInt64
  {% else %}
    alias SizeT = UInt32
  {% end %}

  fun abort : NoReturn
  fun exit(Int32) : NoReturn
  fun puts(UInt8*) : Int32
  fun printf(UInt8*, ...) : Int32
  fun snprintf(UInt8*, SizeT, UInt8*, ...) : Int32
  fun strcmp(UInt8*, UInt8*) : Int32
end
