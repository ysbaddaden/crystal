module Sys
  module Random
    # Fills *buffer* with random bytes from a secure source.
    # def self.random_bytes(buffer : Bytes) : Nil
  end
end

{% if flag?(:linux) %}
  require "./linux/random"
{% else %}
  require "./unix/random"
{% end %}
