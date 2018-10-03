lib LibCrystalMain
  @[Raises]
  fun __crystal_main(argc : Int32, argv : UInt8**)
end

module Crystal
  @@running = false

  # Defines the main routine run by normal Crystal programs:
  #
  # - Initializes the GC
  # - Invokes the given *block*
  # - Handles unhandled exceptions
  # - Invokes `at_exit` handlers
  # - Flushes `STDOUT` and `STDERR`
  #
  # This method can be invoked if you need to define a custom
  # main (as in C main) function, doing all the above steps.
  #
  # For example:
  #
  # ```
  # fun main(argc : Int32, argv : UInt8**) : Int32
  #   Crystal.main do
  #     elapsed = Time.measure do
  #       Crystal.main_user_code(argc, argv)
  #     end
  #     puts "Time to execute program: #{elapsed}"
  #   end
  # end
  # ```
  #
  # Note that the above is really just an example, almost the
  # same can be accomplished with `at_exit`. But in some cases
  # redefinition of C's main is needed.
  def self.main(&block)
    # the garbage collector must be initialized before anything else:
    GC.init

    # initialize the Crystal core foundations, responsible to initialize enough
    # for the main user code, that includes corelib & stdlib initializations, to
    # happen in a fiber:
    Thread.current = Thread.new # main thread's object
    Crystal::EventLoop.init     # I/O, sleep timers, ...
    Crystal::Scheduler.init     # fibers & schedulers

    status = 0

    # main user code is run in a fiber; see `#start_main_loop` for details:
    spawn(name: "main_user_code") do
      begin
        block.call
      rescue ex
        AtExitHandlers.exception = ex
        status = 1
      end

      status = AtExitHandlers.run(status)
      STDOUT.flush
      STDERR.flush
    ensure
      # main program is terminated: break out of the main loop, so `#main` can
      # be resumed and the program will exit
      break_main_loop
    end

    # spawns scheduler threads then blocks until the main user code is finished:
    start_main_loop

    # all done: exit with status
    status
  end

  # Main method run by all Crystal programs at startup.
  #
  # This setups up the GC, invokes your program, rescuing
  # any handled exception, and then runs `at_exit` handlers.
  #
  # This method is automatically invoked for you, so you
  # don't need to invoke it.
  #
  # However, if you need to define a special main C function,
  # you can redefine main and invoke `Crystal.main` from it:
  #
  # ```
  # fun main(argc : Int32, argv : UInt8**) : Int32
  #   # some setup before Crystal main
  #   Crystal.main(argc, argv)
  #   # some cleanup logic after Crystal main
  # end
  # ```
  #
  # The `Crystal.main` can also be passed as a callback:
  #
  # ```
  # fun main(argc : Int32, argv : UInt8**) : Int32
  #   LibFoo.init_foo_and_invoke_main(argc, argv, ->Crystal.main)
  # end
  # ```
  #
  # Note that before `Crystal.main` is invoked the GC
  # is not setup yet, so nothing that allocates memory
  # in Crystal (like `new` for classes) can be used.
  def self.main(argc : Int32, argv : UInt8**)
    main do
      main_user_code(argc, argv)
    end
  end

  # Executes the main user code. This normally is executed
  # after initializing the GC and before executing `at_exit` handlers.
  #
  # You should never invoke this method unless you need to
  # redefine C's main function. See `Crystal.main` for
  # more details.
  def self.main_user_code(argc : Int32, argv : UInt8**)
    LibCrystalMain.__crystal_main(argc, argv)
  end

  # :nodoc:
  def self.running? : Bool
    @@running
  end

  private def self.mutex
    @@mutex ||= Thread::Mutex.new
  end

  private def self.monitor
    @@monitor ||= Thread::ConditionVariable.new
  end

  # Start the main crystal loop. This will start the scheduler threads then
  # block until `break_main_loop` is eventually called from the main user
  # code fiber.
  private def self.start_main_loop : Nil
    mutex.synchronize do
      @@running = true

      # TODO: block standard signal delivery with pthread_sigmask, so started
      #       threads won't receive any standard signal (they inherit the
      #       current thread's sigmask).

      # spawn the scheduler threads, we always start at least one thread in
      # addition to the main thread because the main thread will block!
      NPROCS.times do
        Thread.new do
          Thread.log "start", Thread.current.scheduler.@main

          begin
            Thread.current.scheduler.start
          rescue ex
            fatal(ex, "Unexpected Crystal::Scheduler exception")
          end

          Thread.log "stop", Thread.current.scheduler.@main
          # TODO: notify that the scheduler has stopped
        end
      end

      # TODO: unblock standard signal delivery with pthread_sigmask, so the main
      #       thread will be the only one to receive & handle signals.

      # block until `main` has terminated; unblocks temporarily once in a while
      # to execute some cleanup operations
      while running?
        monitor.timedwait(mutex, 5.seconds) do
          Fiber.stack_pool.collect
        end
      end

      # TODO: unpark threads & wait for them to be terminated
    end
  end

  # Tells scheduler threads to stop and resumes the main thread.
  private def self.break_main_loop : Nil
    mutex.synchronize do
      @@running = false
      monitor.broadcast
    end
  end

  private def self.fatal(exception, message) : NoReturn
    STDERR.print message
    STDERR.print ": "
    exception.inspect_with_backtrace(STDERR)
    STDERR.flush
    exit(1)
  end
end

# Main function that acts as C's main function.
# Invokes `Crystal.main`.
#
# Can be redefined. See `Crystal.main` for examples.
fun main(argc : Int32, argv : UInt8**) : Int32
  Crystal.main(argc, argv)
end
