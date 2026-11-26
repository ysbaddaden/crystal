struct Float64
  def abs
    self < 0.0 ? 0.0 - self : self
  end
end
