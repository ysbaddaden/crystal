struct Nil
  def ==(other : Nil)
    true
  end

  def not_nil! : NoReturn
    raise NilAssertionError.new
  end
end
