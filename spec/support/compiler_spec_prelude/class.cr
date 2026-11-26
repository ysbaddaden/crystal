class Class
  def name : String
    {{ @type.name.stringify }}
  end

  def ===(other)
    {% if @type == Class %}
      other.is_a?(Class)
    {% else %}
      other.is_a?(self)
    {% end %}
  end
end
