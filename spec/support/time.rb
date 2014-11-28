class Fixnum
  def seconds
    self * 1000
  end
  alias :second :seconds

  def milliseconds
    self
  end
  alias :millisecond :milliseconds
end

