require "base64"
require "random/pcg32"

# `Random` provides an interface for random values generation, using a pseudo random number generator (PRNG).
#
# ```
# Random.new_seed # => 112705036
# Random.rand     # => 0.167595
# Random.rand(5)  # => 2
# ```
#
# The above methods delegate to a `Random` instance.
#
# ```
# r = Random.new
# r.rand      # => 0.0372991
# r.next_bool # => true
# r.next_int  # => 2223112
# ```
#
# This module also defines a global method `#rand`, which `Array#sample` and `Array#shuffle` delegates.
#
# ```
# rand     # => 0.293829
# rand(10) # => 8
# ```
#
# An instance of each class that includes `Random` is a random number generator with its own state.
# Usually such RNGs can be initialized with a seed, which defines their initial state. It is
# guaranteed that after initializing two different instances with the same seed, and then executing
# the same calls on both of them, you will get the same results. This allows exactly reproducing the
# same seemingly random events by just keeping the seed.
#
# It is possible to make a custom RNG by including `Random` and implementing `next_u` to return an
# unsigned number of a pre-determined type (usually `UInt32`). The numbers generated by your RNG
# must be uniformly distributed in the whole range of possible values for that type (e.g.
# `0u32..UInt32::MAX`). This allows all other methods of `Random` to be based on this and still
# produce uniformly distributed results. Your `Random` class should also have a way to initialize
# it. For pseudo-random number generators that will usually be an integer seed, but there are no
# rigid requirements for the initialization.
#
# The default PRNG is `Random::PCG32` which has a good overall statistical
# distribution (low bias of generated numbers) and is fast for overall usages on
# different platforms, but isn't cryptographically secure. If a third party has
# access to some generated numbers, she may deduce incoming numbers, putting
# your application at risk.
#
# It is recommended to use a secure source, such as `Random::System`,
# `Random::ISAAC` or ChaCha20 for anything that needs security, such as online
# games, identification tokens, salts, initializing a PRNG, ... These PRNG are
# slower but cryptographically secure, so a third party can't deduce incoming
# numbers.
module Random
  DEFAULT = PCG32.new

  # Initializes an instance with the given *seed* and *sequence*.
  def self.new(seed, sequence = 0_u64)
    PCG32.new(seed.to_u64, sequence)
  end

  # Initializes an instance seeded from a system source.
  def self.new
    PCG32.new
  end

  # Generates a random unsigned integer.
  #
  # The integers must be uniformly distributed between `0` and
  # the maximal value for the chosen type.
  abstract def next_u : UInt

  # Generates a random `Bool`.
  #
  # ```
  # Random.new.next_bool # => true
  # ```
  def next_bool : Bool
    next_u.odd?
  end

  # Same as `rand(Int32::MIN..Int32::MAX)`.
  def next_int : Int32
    rand_type(Int32)
  end

  # See `#rand`.
  def next_float : Float64
    max_prec = 1u64 << 53 # Float64, excluding mantissa, has 2^53 values
    rand(max_prec) / (max_prec - 1).to_f64
  end

  # Generates a random `Float64` between `0` and `1`.
  #
  # ```
  # r = Random.new
  # r.rand # => 0.167595
  # r.rand # => 0.0372991
  # ```
  def rand : Float64
    next_float
  end

  # Generates a random integer which is greater than or equal to `0`
  # and less than *max*.
  #
  # The return type always matches the supplied argument.
  #
  # ```
  # Random.new.rand(10)   # => 5
  # Random.new.rand(5000) # => 2243
  # ```
  def rand(max : Int) : Int
    rand_int(max)
  end

  {% for size in [8, 16, 32, 64] %}
    {% utype = "UInt#{size}".id %}
    {% for type in ["Int#{size}".id, utype] %}
      private def rand_int(max : {{type}}) : {{type}}
        unless max > 0
          raise ArgumentError.new "Invalid bound for rand: #{max}"
        end

        # The basic ideas of the algorithm are best illustrated with examples.
        #
        # Let's say we have a random number generator that gives uniformly distributed random
        # numbers between 0 and 15. We need to get a uniformly distributed random number between
        # 0 and 5 (*max* = 6). The typical mistake made in this case is to just use `rand() % 6`,
        # but it is clear that some results will appear more often than others. So, the surefire
        # approach is to make the RNG spit out numbers until it gives one inside our desired range.
        # That is really wasteful though. So the approach taken here is to discard only a small
        # range of the possible generated numbers, and use the modulo operation on the "valid" ones,
        # like this (where X means "discard and try again"):
        #
        # Generated number:  0  1  2  3  4  5  6  7  8  9 10 11 12 13 14 15
        #           Result:  0  1  2  3  4  5  0  1  2  3  4  5  X  X  X  X
        #
        # 12 is the *limit* here - the highest number divisible by *max* while still being within
        # bounds of what the RNG can produce.
        #
        # On the other side of the spectrum is the problem of generating a random number in a higher
        # range than what the RNG can produce. Let's say we have the same mentioned RNG, but we need
        # a uniformly distributed random number between 0 and 255. All that needs to be done is to
        # generate two random numbers between 0 and 15, and combine their bits
        # (i.e. `rand()*16 + rand()`).
        #
        # Using a combination of these tricks, any RNG can be turned into any RNG, however, there
        # are several difficult parts about this. The code below uses as few calls to the underlying
        # RNG as possible, meaning that (with the above example) with *max* being 257, it would call
        # the RNG 3 times. (Of course, it doesn't actually deal with RNGs that produce numbers
        # 0 to 15, only with the `UInt8`, `UInt16`, `UInt32` and `UInt64` ranges.
        #
        # Another problem is how to actually compute the *limit*. The obvious way to do it, which is
        # `(RAND_MAX + 1) / max * max`, fails because `RAND_MAX` is usually already the highest
        # number that an integer type can hold. And even the *limit* itself will often be
        # `RAND_MAX + 1`, meaning that we don't have to discard anything. The ways to deal with this
        # are described below.

        # if max - 1 <= typeof(next_u)::MAX
        if typeof(next_u).new(max - 1) == max - 1
          # One number from the RNG will be enough.
          # All the computations will (almost) fit into `typeof(next_u)`.

          # Relies on integer overflow + wraparound to find the highest number divisible by *max*.
          limit = typeof(next_u).new(0) - (typeof(next_u).new(0) - max) % max
          # *limit* might be 0, which means it would've been `typeof(next_u)::MAX + 1, but didn't
          # fit into the integer type.

          loop do
            result = next_u

            # For a uniform distribution we may need to throw away some numbers
            if result < limit || limit == 0
              return {{type}}.new(result % max)
            end
          end
        else
          # We need to find out how many random numbers need to be combined to be able to generate a
          # random number of this magnitude.
          # All the computations will be based on `{{utype}}` as the larger type.

          # `rand_max - 1` is the maximal number we can get from combining `needed_parts` random
          # numbers.
          # Compute *rand_max* as `(typeof(next_u)::MAX + 1) ** needed_parts)`.
          # If *rand_max* overflows, that means it has reached `high({{utype}}) + 1`.
          rand_max = {{utype}}.new(1) << (sizeof(typeof(next_u))*8)
          needed_parts = 1
          while rand_max < max && rand_max > 0
            rand_max <<= sizeof(typeof(next_u))*8
            needed_parts += 1
          end

          limit =
            if rand_max > 0
              # `rand_max` didn't overflow, so we can calculate the *limit* the straightforward way.
              rand_max / max * max
            else
              # *rand_max* is `{{utype}}::MAX + 1`, need the same wraparound trick. *limit* might
              # overflow, which means it would've been `{{utype}}::MAX + 1`, but didn't fit into
              # the integer type.
              {{utype}}.new(0) - ({{utype}}.new(0) - max) % max
            end

          loop do
            result = rand_type({{utype}}, needed_parts)

            # For a uniform distribution we may need to throw away some numbers.
            if result < limit || limit == 0
              return {{type}}.new(result % max)
            end
          end
        end
      end

      private def rand_range(range : Range({{type}}, {{type}})) : {{type}}
        span = {{utype}}.new(range.end - range.begin)
        if range.excludes_end?
          unless range.begin < range.end
            raise ArgumentError.new "Invalid range for rand: #{range}"
          end
        else
          unless range.begin <= range.end
            raise ArgumentError.new "Invalid range for rand: #{range}"
          end
          if range.begin == {{type}}::MIN && range.end == {{type}}::MAX
            return rand_type({{type}})
          end
          span += 1
        end
        range.begin + {{type}}.new(rand_int(span))
      end

      # Generates a random integer in range `{{type}}::MIN..{{type}}::MAX`.
      private def rand_type(type : {{type}}.class, needed_parts = sizeof({{type}}) / sizeof(typeof(next_u))) : {{type}}
        # Build up the number combining multiple outputs from the RNG.
        result = {{utype}}.new(next_u)
        (needed_parts - 1).times do
          result <<= sizeof(typeof(next_u))*8
          result |= {{utype}}.new(next_u)
        end
        {{type}}.new(result)
      end
    {% end %}
  {% end %}

  # Returns a random `Float64` which is greater than or equal to `0`
  # and less than *max*.
  #
  # ```
  # Random.new.rand(3.5)    # => 2.88938
  # Random.new.rand(10.725) # => 7.70147
  # ```
  def rand(max : Float) : Float64
    unless max > 0
      raise ArgumentError.new "Invalid bound for rand: #{max}"
    end
    max_prec = 1u64 << 53 # Float64, excluding mantissa, has 2^53 values
    rand(max_prec) / max_prec.to_f64 * max
  end

  # Returns a random integer in the given *range*.
  #
  # The return type always matches the supplied argument.
  #
  # ```
  # Random.new.rand(10..20)                 # => 14
  # Random.new.rand(Int64::MIN..Int64::MAX) # => -5297435808626736140
  # ```
  def rand(range : Range(Int, Int)) : Int
    rand_range(range)
  end

  # Returns a random `Float64` in the given *range*.
  #
  # ```
  # Random.new.rand(6.2..21.768) # => 15.2989
  # ```
  def rand(range : Range(Float, Float)) : Float64
    span = range.end - range.begin
    if range.excludes_end?
      unless range.begin < range.end
        raise ArgumentError.new "Invalid range for rand: #{range}"
      end
      range.begin + rand(span)
    else
      unless range.begin <= range.end
        raise ArgumentError.new "Invalid range for rand: #{range}"
      end
      range.begin + rand * span
    end
  end

  # Fills a given slice with random bytes.
  #
  # ```
  # slice = Bytes.new(4) # => [0, 0, 0, 0]
  # Random.new.random_bytes(slice)
  # slice # => [217, 118, 38, 196]
  # ```
  def random_bytes(buf : Bytes) : Nil
    n = buf.size / sizeof(typeof(next_u))
    remaining = buf.size - n * sizeof(typeof(next_u))

    slice = buf.to_unsafe.as(typeof(next_u)*).to_slice(n)
    slice.each_index { |i| slice[i] = next_u }

    if remaining > 0
      bytes = next_u
      remaining.times do |i|
        bits = i * 8
        mask = typeof(next_u).new(0xff << bits)
        buf[-i - 1] = UInt8.new((bytes & mask) >> bits)
      end
    end
  end

  # Generates a slice filled with *n* random bytes.
  #
  # ```
  # Random.new.random_bytes    # => [145, 255, 191, 133, 132, 139, 53, 136, 93, 238, 2, 37, 138, 244, 3, 216]
  # Random.new.random_bytes(4) # => [217, 118, 38, 196]
  # ```
  def random_bytes(n : Int = 16) : Bytes
    raise ArgumentError.new "Negative size: #{n}" if n < 0
    Bytes.new(n).tap { |buf| random_bytes(buf) }
  end

  # Generates *n* random bytes that are encoded into base64.
  #
  # Check `Base64#strict_encode` for details.
  #
  # ```
  # Random::System.base64(4) # => "fK1eYg=="
  # ```
  #
  # It is recommended to use the secure `Random::System` as a source or another
  # cryptographically quality PRNG such as `Random::ISAAC` or ChaCha20.
  def base64(n : Int = 16) : String
    Base64.strict_encode(random_bytes(n))
  end

  # URL-safe variant of `#base64`.
  #
  # Check `Base64#urlsafe_encode` for details.
  #
  # ```
  # Random::System.urlsafe_base64                    # => "MAD2bw8QaBdvITCveBNCrw"
  # Random::System.urlsafe_base64(8, padding: true)  # => "vvP1kcs841I="
  # Random::System.urlsafe_base64(16, padding: true) # => "og2aJrELDZWSdJfVGkxNKw=="
  # ```
  #
  # It is recommended to use the secure `Random::System` as a source or another
  # cryptographically quality PRNG such as `Random::ISAAC` or ChaCha20.
  def urlsafe_base64(n : Int = 16, padding = false) : String
    Base64.urlsafe_encode(random_bytes(n), padding)
  end

  # Generates a hexadecimal string based on *n* random bytes.
  #
  # The bytes are encoded into a string of two-digit hexadecimal
  # number (00-ff) per byte.
  #
  # ```
  # Random::System.hex    # => "05f100a1123f6bdbb427698ab664ff5f"
  # Random::System.hex(1) # => "1a"
  # ```
  #
  # It is recommended to use the secure `Random::System` as a source or another
  # cryptographically quality PRNG such as `Random::ISAAC` or ChaCha20.
  def hex(n : Int = 16) : String
    random_bytes(n).hexstring
  end

  # Generates a UUID (Universally Unique Identifier).
  #
  # It generates a random v4 UUID. See
  # [RFC 4122 Section 4.4](https://tools.ietf.org/html/rfc4122#section-4.4)
  # for the used algorithm and its implications.
  #
  # ```
  # Random::System.uuid # => "a4e319dd-a778-4a51-804e-66a07bc63358"
  # ```
  #
  # It is recommended to use the secure `Random::System` as a source or another
  # cryptographically quality PRNG such as `Random::ISAAC` or ChaCha20.
  def uuid : String
    bytes = random_bytes(16)
    bytes[6] = (bytes[6] & 0x0f) | 0x40
    bytes[8] = (bytes[8] & 0x3f) | 0x80

    String.new(36) do |buffer|
      buffer[8] = buffer[13] = buffer[18] = buffer[23] = 45_u8
      bytes[0, 4].hexstring(buffer + 0)
      bytes[4, 2].hexstring(buffer + 9)
      bytes[6, 2].hexstring(buffer + 14)
      bytes[8, 2].hexstring(buffer + 19)
      bytes[10, 6].hexstring(buffer + 24)
      {36, 36}
    end
  end

  # See `#rand`.
  def self.rand : Float64
    DEFAULT.rand
  end

  # See `#rand(x)`.
  def self.rand(x)
    DEFAULT.rand(x)
  end
end

# See `Random#rand`.
def rand
  Random.rand
end

# See `Random#rand(x)`.
def rand(x)
  Random.rand(x)
end
