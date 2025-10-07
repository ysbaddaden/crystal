# struct Crystal::System::Semaphore
#   def initialize(value : Int)
#   end
#
#   def wait(timeout : Time::Span) : Bool
#   end
#
#   def wait(timeout : Nil) : Nil
#   end
#
#   def wake : Nil
#   end
#
#   def destroy : Nil
#   end
# end

{% if flag?(:unix) && !flag?(:darwin) %}
  require "./unix/semaphore"
{% end %}
