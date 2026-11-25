# Stores a single key and value for codegen specs.
class Hash(K, V)
  def initialize
    @key = uninitialized K
    @value = uninitialized V
    @has_entry = false
  end

  def []=(key : K, value : V) : V
    @key = key
    @value = value
    @has_entry = true
    value
  end

  def [](key : K) : V
    return @value if @has_entry && @key == key
    LibC.abort
  end

  def each_value(& : V ->)
    yield @value if @has_entry
  end
end

lib LibC
  fun abort : NoReturn
end
