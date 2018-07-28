require "event"
require "thread"

module Crystal
  # :nodoc:
  class Scheduler
    @runnables = Deque(Fiber).new

    def enqueue(fiber : Fiber) : Nil
      @runnables << fiber
    end

    def enqueue(fibers : Enumerable(Fiber)) : Nil
      @runnables.concat fibers
    end

    def reschedule : Nil
      if runnable = @runnables.shift?
        runnable.resume
      else
        Crystal.event_loop.resume
      end
    end
  end

  def self.scheduler
    Thread.current.current_scheduler
  end

  def self.scheduler?
    Thread.current.current_scheduler?
  end
end
