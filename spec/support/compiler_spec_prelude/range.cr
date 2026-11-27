struct Range(B, E)
  include Enumerable(B)

  def initialize(@begin : B, @end : E, @exclusive : Bool = false)
  end

  def begin
    @begin
  end

  def end
    @end
  end

  def each(&) : Nil
    current = @begin
    limit = @end

    while limit.nil? || current < limit
      yield current
      current = current.succ
    end
  end
end
