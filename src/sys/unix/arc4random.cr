require "c/stdlib"

module Sys
  module Random
    # Fills buffer with random bytes using arc4random.
    #
    # NOTE: only secure on OpenBSD and CLoudABI
    def self.random_bytes(buf : Bytes) : Nil
      LibC.arc4random_buf(buf.to_unsafe.as(Void*), buf.size)
    end
  end
end
