lib LibC
  UMTX_OP_WAIT_UINT_PRIVATE = 15
  UMTX_OP_WAKE_PRIVATE      = 16

  fun _umtx_op(Void*, Int, ULong, Void*, Void*)
end
