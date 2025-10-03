lib LibC
  {% target = env("MACOSX_DEPLOYMENT_TARGET") || "0.0" %}

  {% if compare_versions(target, "14.4") >= 0 %}
    OS_SYNC_WAIT_ON_ADDRESS_NONE = 0
    OS_SYNC_WAKE_BY_ADDRESS_NONE = 0

    fun os_sync_wait_on_address(Void*, UInt64, SizeT, UInt32)
    fun os_sync_wait_on_address_with_timeout(Void*, UInt64, SizeT, UInt32, UInt32, UInt64)
    fun os_sync_wake_by_address_all(Void*, SizeT, UInt32)
    fun os_sync_wake_by_address_any(Void*, SizeT, UInt32)
  {% else %}
    # This is an undocumented internal API.
    # See <https://outerproduct.net/futex-dictionary.html>
    UL_COMPARE_AND_WAIT =          1_u32
    ULF_WAKE_ALL        = 0x00000100_u32

    fun __ulock_wait(UInt32, Void*, UInt64, UInt32) : LibC::Int
    {% if compare_versions(target, "11.0") >= 0 %}
      fun __ulock_wait2(UInt32, Void*, UInt64, UInt64, UInt64) : LibC::Int
    {% end %}
    fun __ulock_wake(UInt32, Void*, UInt64) : LibC::Int
  {% end %}
end
