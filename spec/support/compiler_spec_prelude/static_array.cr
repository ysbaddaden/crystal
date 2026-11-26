struct StaticArray(T, N)
  def fill(&)
    index = 0
    buffer = pointerof(@buffer)
    while index < N
      (buffer + index.to_i64!).value = yield index
      index += 1
    end
    self
  end

  def sum
    total = 0
    index = 0
    buffer = pointerof(@buffer)
    while index < N
      total += (buffer + index.to_i64!).value
      index += 1
    end
    total
  end
end
