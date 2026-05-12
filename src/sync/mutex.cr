require "./mu"
require "./type"
require "./errors"
require "./lockable"

{% if flag?(:deadlock) %}
  class Fiber
    # :nodoc:
    getter(__sync_locked : Array(Sync::Mutex)) { [] of Sync::Mutex }
  end
{% end %}

module Sync
  # A mutual exclusion lock to protect critical sections.
  #
  # A single fiber can acquire the lock at a time. No other fiber can acquire
  # the lock while a fiber holds it.
  #
  # This lock can for example be used to protect the access to some resources,
  # with the guarantee that only one section of code can ever read, write or
  # mutate said resources.
  #
  # NOTE: Consider `Exclusive(T)` to protect a value `T` with a `Mutex`.
  class Mutex
    include Lockable

    def initialize(@type : Type = :checked)
      @counter = 0
      @mu = MU.new
    end

    # Acquires the exclusive lock for the duration of the block. The lock will
    # be released automatically before returning, or if the block raises an
    # exception.
    def synchronize(& : -> _)
      lock
      begin
        yield
      ensure
        unlock
      end
    end

    # Acquires the exclusive lock.
    def lock : Nil
      unless @mu.try_lock?
        before_park = nil

        unless @type.unchecked?
          if owns_lock?
            raise Error::Deadlock.new("Can't lock mutex recursively") unless @type.reentrant?
            @counter += 1
            return
          end
          {% if flag?(:deadlock) %}
            before_park = ->deadlock_detection
          {% end %}
        end

        @mu.lock_slow(before_park)
      end

      unless @type.unchecked?
        set_owner
      end
    end

    {% if flag?(:deadlock) %}
      private def deadlock_detection : Nil
        return unless owner = @locked_by

        Fiber.current.__sync_locked.each do |lock|
          next unless lock.@mu.waiting?(owner)
          raise Error::Deadlock.new("Can't lock mutex already locked by #{lock.@locked_by} and waiting on #{lock} locked by the current fiber)")
        end
      end
    {% end %}

    # Releases the exclusive lock.
    def unlock : Nil
      unless @type.unchecked?
        unless owns_lock?
          message =
            if @locked_by
              "Can't unlock Sync::Mutex locked by another fiber"
            else
              "Can't unlock Sync::Mutex that isn't locked"
            end
          raise Error.new(message)
        end
        if @type.reentrant?
          return unless (@counter -= 1) == 0
        end
        unset_owner
      end
      @mu.unlock
    end

    protected def wait(cv : Pointer(CV)) : Nil
      counter = 1

      unless @type.unchecked?
        if @mu.held?
          raise Error.new("Can't unlock Sync::Mutex locked by another fiber") unless owns_lock?
          unset_owner
          counter, @counter = @counter, 0 if @type.reentrant?
        else
          raise Error.new("Can't unlock Sync::Mutex that isn't locked")
        end
      end

      cv.value.wait pointerof(@mu)

      unless @type.unchecked?
        set_owner(counter)
      end
    end

    private def set_owner(counter = 1) : Nil
      @locked_by = fiber = Fiber.current
      @counter = counter if @type.reentrant?

      {% if flag?(:deadlock) %}
        fiber.__sync_locked << self
      {% end %}
    end

    private def unset_owner : Nil
      fiber, @locked_by = @locked_by, nil

      {% if flag?(:deadlock) %}
        fiber.as(Fiber).__sync_locked.delete(pointerof(@mu))
      {% end %}
    end

    protected def owns_lock? : Bool
      @locked_by == Fiber.current
    end

    # :nodoc:
    def dup
      {% raise "Can't dup {{@type}}" %}
    end
  end
end
