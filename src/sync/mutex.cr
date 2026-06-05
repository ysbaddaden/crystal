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
      @locked_by = Atomic(Fiber?).new(nil)
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
      if @mu.try_lock?
        set_owner unless @type.unchecked?
      elsif @type.unchecked?
        @mu.lock_slow
      else
        lock_slow
      end
    end

    @[NoInline]
    private def lock_slow : Nil
      if owns_lock?
        unless @type.reentrant?
          raise Error::Deadlock.new("Can't lock mutex recursively", Fiber.current, Fiber.current, self, self)
        end
        @counter += 1
        return
      end

      @mu.lock_slow do
        {% if flag?(:deadlock) %}
          # no owner; at worst the owner just unlocked and thus can't be
          # waiting on any lock we own (no deadlock, yet)
          next unless owner = @locked_by.get(:relaxed)

          fiber = Fiber.current
          fiber.__sync_locked.each do |lock|
            # is the lock's owner waiting on any lock the current fiber owns?
            next unless lock.@mu.waiting?(owner)

            # Yes? deadlock!

            # TODO: add *owner* to a list of tainted fibers on this lock, the
            # owner shall verify it after acquiring the lock, and when present
            # unlock and also raise a deadlock exception.

            f1 = fiber.name || "0x#{fiber.object_id.to_s(16)}"
            f2 = owner.name || "0x#{owner.object_id.to_s(16)}"
            message = "Fiber A (#{f1}) holds mutex1 and waits for mutex2, while fiber B (#{f2}) holds mutex2 and waits for mutex1"
            raise Error::Deadlock.new(message, fiber, owner, lock, self)
          end
        {% end %}
      end

      set_owner
    end

    # Releases the exclusive lock.
    def unlock : Nil
      unless @type.unchecked?
        unless owns_lock?
          message =
            if @locked_by.lazy_get
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
      {% if flag?(:deadlock) %}
        fiber = Fiber.current
        @locked_by.set(fiber, :relaxed)
        fiber.__sync_locked << self
      {% else %}
        @locked_by.lazy_set(fiber)
      {% end %}

      @counter = counter if @type.reentrant?
    end

    private def unset_owner : Nil
      fiber = @locked_by.lazy_get
      @locked_by.set(nil, :relaxed)

      {% if flag?(:deadlock) %}
        fiber.__sync_locked.delete(self)
      {% end %}
    end

    protected def owns_lock? : Bool
      @locked_by.lazy_get == Fiber.current
    end

    # :nodoc:
    def dup
      {% raise "Can't dup {{@type}}" %}
    end
  end
end
