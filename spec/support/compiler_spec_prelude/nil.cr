{% unless @top_level.has_method?(:raise) %}
  require "./exceptions"
{% end %}

class Object
  def not_nil!
    self
  end
end

struct Nil
  def ==(other : Nil)
    true
  end

  def not_nil! : NoReturn
    raise "unexpected nil"
  end
end
