# Crystal adaptation of "cv" from the "nsync" library with adaptations by
# Justine Alexandra Roberts Tunney in the "cosmopolitan" C library.
#
# Copyright 2016 Google Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# References:
# - <https://github.com/google/nsync>
# - <https://github.com/jart/cosmopolitan/tree/master/third_party/nsync/>

require "../dll"
require "./mu"
require "./waiter"

class Thread
  # :nodoc:
  struct CV
    SPINLOCK  = 1_u32
    NON_EMPTY = 2_u32

    def initialize
      @word = Atomic(UInt32).new(0_u32)
      @waiters = Crystal::Dll(Waiter).new
    end

    def wait(mu : Pointer(MU), timeout : Time::Span? = nil) : Bool
      waiter = Waiter.init(waiter_type(mu), mu)
      begin
        waiter.value.waiting!

        old_word = acquire_spinlock(set: NON_EMPTY)
        @waiters.push(waiter)
        remove_count = waiter.value.remove_count # NOTE: always zero
        release_spinlock(old_word | NON_EMPTY)

        if waiter.value.writer?
          mu.value.unlock
        else
          mu.value.runlock
        end

        timed_out = wait_impl(waiter, remove_count, timeout)
        relock(mu, waiter)

        timed_out
      ensure
        waiter.value.destroy
      end
    end

    private def relock(mu, waiter)
      # reacquire mu
      if cv_mu = waiter.value.cv_mu
        # waiter was woken from cv, and must re-acquire mu
        if waiter.value.writer?
          cv_mu.value.lock
        else
          cv_mu.value.rlock
        end
      else
        # waiter was moved to mu's queue, then woken from mu and is thus a
        # designated waker, but it didn't lock yet and must enter the lock loop
        # and clear the DESIG_WAKER flag
        mu.value.lock_slow(waiter, clear: MU::DESIG_WAKER)
      end
    end

    private def wait_impl(waiter, remove_count, timeout)
      sem_expired = false
      expired = false
      attempts = 0

      while waiter.value.@waiting.get(:acquire)
        sem_expired ||= waiter.value.sem_wait(timeout)

        if sem_expired && waiter.value.waiting?
          # timeout expired and no wakeup, acquire spinlock & confirm
          old_word = acquire_spinlock

          # check that waiter wasn't removed from the queue after we checked
          # above, but before we acquired the spinlock; the test of remove_count
          # confirms that the waiter is still governed by this CV's spinlock;
          # otherwise some other thread is about to set waiting = false
          if waiter.value.waiting?
            if remove_count == waiter.value.remove_count
              # still in @waiters
              # not woken, so remove waiter, and declare a timeout
              expired = true
              @waiters.delete(waiter)
              waiter.value.increment_remove_count
              old_word &= ~NON_EMPTY if @waiters.empty?
              waiter.value.@waiting.set(false, :release)
            end
          end

          release_spinlock(old_word)
        end

        break unless waiter.value.waiting?

        # the delay here causes this thread ultimately to yield to another
        # that has dequeued this thread, but has not yet set the waiting field
        # to zero; a timeout may prevent this thread from blocking above on
        # the semaphore.
        attempts = Thread.delay(attempts)
      end

      expired
    end

    def signal : Nil
      word = @word.get(:acquire)
      return if (word & NON_EMPTY) == 0

      wake = Crystal::Dll(Waiter).new
      all_readers = false

      old_word = acquire_spinlock

      if first_waiter = @waiters.shift?
        first_waiter.value.increment_remove_count
        wake.push(first_waiter)

        if first_waiter.value.reader?
          # first waiter is a reader: wake all readers, and one writer (if any),
          # this allows all shared accesses to be resumed, while still allowing
          # only one exclusive access
          all_readers = true
          woke_writer = false

          @waiters.each do |waiter|
            if waiter.value.writer?
              next if woke_writer
              all_readers = false
              woke_writer = true
            end

            @waiters.delete(waiter)
            waiter.value.increment_remove_count
            wake.push(waiter)
          end
        end

        if @waiters.empty?
          old_word &= ~NON_EMPTY
        end
      end

      release_spinlock(old_word)

      wake_waiters pointerof(wake), all_readers
    end

    def broadcast : Nil
      word = @word.get(:acquire)
      return if (word & NON_EMPTY) == 0

      wake = Crystal::Dll(Waiter).new
      all_readers = true

      old_word = acquire_spinlock

      # wake all waiters
      while waiter = @waiters.shift?
        all_readers = false if waiter.value.writer?
        waiter.value.increment_remove_count
        wake.push(waiter)
      end

      release_spinlock(old_word & ~NON_EMPTY)

      wake_waiters pointerof(wake), all_readers
    end

    private def wake_waiters(wake, all_readers)
      # FIXME: transfer leads to SEGFAULTS (even with waiters allocated in GC HEAP)
      first_waiter = wake.value.first?
      return if first_waiter.null?

      # try to transfer to mu's queue
      if mu = first_waiter.value.cv_mu
        mu.value.try_transfer(wake, first_waiter, all_readers)
      end

      # wake waiters that didn't get transferred
      wake.value.consume_each(&.value.wake)
    end

    private def waiter_type(mu)
      is_writer = mu.value.held?
      is_reader = mu.value.rheld?

      if is_writer
        if is_reader
          raise "BUG: MU is held in reader and writer mode simultaneously on entry to CV#wait"
        end
        Waiter::Type::Writer
      elsif is_reader
        Waiter::Type::Reader
      else
        raise "BUG: MU not held on entry to CV#wait"
      end
    end

    private def acquire_spinlock(set = 0_u32)
      attempts = 0

      while true
        word = @word.get(:relaxed)

        if (word & SPINLOCK) == 0
          _, success = @word.compare_and_set(word, word | SPINLOCK | set, :acquire, :relaxed)
          return word if success
        end

        attempts = Thread.delay(attempts)
      end
    end

    private def release_spinlock(word)
      @word.set(word & ~SPINLOCK, :release)
    end
  end
end
