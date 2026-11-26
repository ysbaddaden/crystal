require "./indexable"

struct Tuple
  include Indexable(Union(*T))

  def self.new(*args)
    args
  end

  def size
    {{T.size}}
  end

  def each(& : Union(*T) ->) : Nil
    {% for i in 0...T.size %}
      yield self[{{i}}]
    {% end %}
  end

  def +(other : U) forall U
    {% begin %}
      Tuple.new(
        {% for i in 0...T.size %}
          self[{{i}}],
        {% end %}
        {% for i in 0...U.size %}
          other[{{i}}],
        {% end %}
      )
    {% end %}
  end
end
