# Supports hash-literal lowering in semantic-only inputs.
class Hash(K, V)
  def []=(key : K, value : V) : V
    value
  end
end
