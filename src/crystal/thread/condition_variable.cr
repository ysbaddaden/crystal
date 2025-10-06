require "./cv"

class Thread
  class ConditionVariable
    def initialize
      @cv = CV.new
    end

    def wait(mutex : Thread::Mutex) : Nil
      mutex.wait { |mu| @cv.wait(mu) }
    end

    def wait(mutex : Thread::Mutex, time : Time::Span, & : ->) : Nil
      if mutex.wait { |mu| @cv.wait(mu, time) }
        yield
      end
    end

    def signal : Nil
      @cv.signal
    end

    def broadcast : Nil
      @cv.broadcast
    end
  end
end
