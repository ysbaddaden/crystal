class Regex
  enum Options
    None
  end

  def initialize(@pattern : String, @options : Options)
  end

  def ==(other : Regex)
    @pattern == other.@pattern
  end
end
