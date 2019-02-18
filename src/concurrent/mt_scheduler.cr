require "./mt_runnables"

# :nodoc:
#
# Schedulers are tied to a thread, and must only ever be accessed from within
# this thread.
#
# Only the class methods are public and safe to use. Instance methods are
# protected and must never be called directly.
class Crystal::Scheduler
  @@mutex = uninitialized Thread::Mutex
  @@all_runnables = uninitialized Array(Crystal::Scheduler::Runnables)

  def self.init
    @@mutex = Thread::Mutex.new
    @@all_runnables = Array(Crystal::Scheduler::Runnables).new(Crystal::NPROCS + 1)
    # allocate the main scheduler:
    Thread.current.scheduler
  end

  def self.current_fiber : Fiber
    Thread.current.scheduler.@current
  end

  def self.enqueue(fiber : Fiber) : Nil
    Thread.current.scheduler.enqueue(fiber)
  end

  def self.enqueue(fibers : Enumerable(Fiber)) : Nil
    Thread.current.scheduler.enqueue(fibers)
  end

  def self.reschedule : Nil
    Thread.current.scheduler.reschedule
  end

  def self.resume(fiber : Fiber) : Nil
    Thread.current.scheduler.resume(fiber)
  end

  def self.sleep(time : Time::Span) : Nil
    Thread.current.scheduler.sleep(time)
  end

  def self.yield : Nil
    Thread.current.scheduler.yield
  end

  def self.yield(fiber : Fiber) : Nil
    Thread.current.scheduler.yield(fiber)
  end

  # :nodoc:
  def initialize(@main : Fiber)
    @current = @main
    @runnables = Crystal::Scheduler::Runnables.new
    @rng = Random::PCG32.new
    @@mutex.synchronize { @@all_runnables << @runnables }
  end

  # :nodoc:
  #
  # The scheduler's main loop. Follows the algorithms from the "Scheduling
  # Multithreaded Computations by Work Stealing" (2001) paper.
  #
  # The main loop runs on the thread's main stack, and first tries to dequeue
  # and resume a fiber from its internal runnables queue.
  #
  # Once the queue is emptied, the scheduler immediately resumes its main loop,
  # and becomes a thief that will repeat the following actions until it gets a
  # runnable fiber that it can resume:
  #
  # 1. passes CPU time to another thread, allowing other threads to progress;
  # 2. tries to steal a fiber from another random scheduler;
  # 3. executes the event loop to try and fill its internal queue.
  #
  # TODO: loop a limited number of time and eventually park the thread to avoid
  #       burning CPU time.
  def start : Nil
    # always process the internal runnables queue on startup:
    if fiber = @runnables.pop?
      resume(fiber)
    end

    # the runnables queue is now empty

    while Crystal.running?
      # 1. yield CPU time to another thread
      Thread.yield

      # 2. try to steal a runnable fiber from a random scheduler:
      fiber = steal_once

      unless fiber
        # 3. process the event loop to fill the runnables queue if any events
        #    are pending, but don't block, since it would prevent this thread
        #    from stealing fibers (or resuming a yielded fiber), and block other
        #    threads, too:
        Crystal::EventLoop.run_nonblock

        # try to dequeue a fiber from the internal runnables queue:
        fiber = @runnables.pop?
      end

      if fiber
        # success: we now have a runnable fiber (dequeued, stolen or ready):
        resume(fiber)

        # the runnables queue is now empty (again)
      end
    end
  end

  protected def steal_once : Fiber?
    runnables = @@all_runnables.sample(@rng)
    runnables.shift? unless runnables == @runnables
  end

  protected def enqueue(fiber : Fiber) : Nil
    @runnables.push(fiber)
    # TODO: wakeup a parked thread (if any)
  end

  protected def enqueue(fibers : Enumerable(Fiber)) : Nil
    fibers.each do |fiber|
      @runnables.push(fiber)
    end
    # TODO: wakeup parked threads (if any)
  end

  protected def resume(fiber : Fiber) : Nil
    # a fiber can be enqueued before saving its context, which means there is a
    # time window for a scheduler to steal and try to resume a fiber before its
    # context has been fully saved, so we wait:
    spin_until_resumable(fiber)

    # replace references:
    current, @current = @current, fiber

    {% unless flag?(:gc_none) %}
      # register the fiber's stack as the current thread's stack to the garbage
      # collector; we disable BDWGC to avoid a race-condition between
      # register-gc-stack and swapcontext during which another thread could call
      # GC_collect and stop-the-world, leaving the GC with an invalid thread
      # stack:
      GC.disable
      GC.stack_bottom = fiber.@stack_bottom
      # GC.set_stack_bottom(LibC.pthread_self, fiber.@stack_bottom)
    {% end %}

    # swap the execution context:
    Fiber.swapcontext(pointerof(current.@context), pointerof(fiber.@context))

    {% unless flag?(:gc_none) %}
      # eventually resume the GC (in the new context)
      GC.enable
    {% end %}
  end

  private def spin_until_resumable(fiber)
    # 1. 1st attempt will always succeed with a single thread (unless the fiber
    #    is dead):
    until fiber.resumable?
      # 2. constant-time busy-loop, to avoid an expensive thread context switch:
      #    relies on a magic number, but anything higher don't seem to improve
      #    performance (on x86_64 at least):
      99.times do
        if fiber.resumable?
          return
        end

        if fiber.dead?
          LibC.dprintf 2, "\nFATAL: tried to resume a dead fiber: #{fiber}\n"
          caller.each { |line| LibC.dprintf(2, "  from #{line}\n") }
          exit 1
        end
      end

      # 3. give up, yield CPU time to another thread (avoid contention):
      Thread.yield
    end
  end

  # Suspends execution of `@current` by saving its context, and resumes another
  # fiber. `@current` is never enqueued and must be manually resumed by another
  # main (event loop, explicit call the `#resume` or `#enqueue`, ...).
  protected def reschedule : Nil
    # try to dequeue the next fiber from the internal runnables queue:
    fiber = @runnables.pop?

    # if the queue was empty, resume the main fiber to resume the scheduler's
    # stealing loop; this allows to save the context of the current fiber, so it
    # can be resumed by another thread without delay (even if the current thread
    # blocks), or even by the same thread if we end up resuming the current
    # fiber:
    fiber ||= @main

    # swap to the new context:
    resume(fiber)
  end

  protected def sleep(time : Time::Span) : Nil
    @current.resume_event.add(time)
    reschedule
  end

  # Very similar to `#reschedule` but enqueues `@current` before switching
  # contexts.
  #
  # Takes care to dequeue a fiber from the runnables queue before `@current` is
  # enqueued, because of the runnables queue algorithm where the scheduler will
  # push/pop from the bottom of the queue —a shift from the top of the queue is
  # reserved for stealing a fiber from another scheduler queue.
  protected def yield : Nil
    # try to dequeue the next fiber from the internal runnables queue:
    fiber = @runnables.pop?

    # if the queue was empty, resume the main fiber to resume the scheduler's
    # stealing loop; this allows to save the context of the current fiber, so it
    # can be resumed by another thread without delay (even if the current thread
    # blocks), or even by the same thread if we end up resuming the current
    # fiber:
    fiber ||= @main

    # enqueue the current fiber, so it can be resumed later or stolen & resumed
    # by another scheduler:
    enqueue(@current)

    # swap to the new context:
    resume(fiber)
  end

  protected def yield(fiber : Fiber) : Nil
    enqueue(@current)
    resume(fiber)
  end
end
