require "../dll"
require "../system/futex"

{% unless Thread.class.has_method?(:wait) %}
  require "../system/semaphore"
{% end %}

class Thread
  # :nodoc:
  struct Waiter
    enum Type
      Reader
      Writer
    end

    include Crystal::Dll::Node

    property cv_mu : Pointer(MU)

    {% if Thread.class.has_method?(:wait) %}
      @sem = Atomic(UInt32).new(0_u32)
    {% else %}
      @sem = Crystal::System::Semaphore.new(0)
    {% end %}

    def initialize(@type : Type, @cv_mu : Pointer(MU) = Pointer(MU).null)
      # protects against spurious wakeups (e.g. EINTR) and timeouts
      @waiting = Atomic(Bool).new(true)

      # determine if the waiter has been transferred (e.g. from CV to MU)
      @remove_count = Atomic(UInt32).new(0_u32)
    end

    def reader? : Bool
      @type.reader?
    end

    def writer? : Bool
      @type.writer?
    end

    def waiting! : Nil
      @waiting.set(true, :relaxed)
    end

    def waiting? : Bool
      @waiting.get(:relaxed)
    end

    def remove_count : UInt32
      @remove_count.get(:relaxed)
    end

    def increment_remove_count : Nil
      @remove_count.add(1_u32, :relaxed)
    end

    def wait : Nil
      while @waiting.get(:acquire)
        sem_wait(nil)
      end
    end

    def sem_wait(timeout : Time::Span?) : Bool
      {% if Thread.class.has_method?(:wait) %}
        # FIXME: timeout shall be a deadline (as per the realtime or monotonic
        # clock) otherwise every retry will restart the timeout and extend the
        # deadline!
        while true
          sem = @sem.get(:relaxed)

          if sem == 0_u32
            timed_out = Thread.wait(pointerof(@sem.@value), sem, timeout)
            return true if timed_out
          else
            _, success = @sem.compare_and_set(sem, sem - 1_u32, :acquire, :relaxed)
            return false if success
          end
        end
      {% else %}
        @sem.wait(timeout)
      {% end %}
    end

    def wake : Nil
      @waiting.set(false, :release)
      sem_wake
    end

    def sem_wake
      {% if Thread.class.has_method?(:wait) %}
        @sem.add(1_u32, :release)
        Thread.wake_one(pointerof(@sem.@value))
      {% else %}
        @sem.wake
      {% end %}
    end

    def destroy
      {% unless Thread.class.has_method?(:wait) %}
        @sem.destroy
      {% end %}
    end
  end
end
