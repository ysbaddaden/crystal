class Thread
  # Compare the value at *address* against *value*. Returns immediately if the
  # values are different, otherwise blocks the current thread until `.wake_one`
  # or `.wake_all` is called for *address* or the optional *timeout* has
  # expired.
  #
  # Returns true if the optional *timeout* expired and false for normal retry
  # behavior (e.g. success, EAGAIN, EINTR).
  #
  # Raises a `RuntimeError` on errors (e.g. EINVAL).
  # def self.wait(address : UInt32*, value : UInt32, timeout : Time::Span? = nil) : Errno
  # end

  # Wake a single thread blocked on *address* (if any).
  # def self.wake_one(address : UInt32*) : Nil
  # end

  # Wake all threads blocked on *address* (if any).
  # def self.wake_all(address : UInt32*) : Nil
  # end
end

{% if flag?(:darwin) %}
  require "./darwin/futex"
{% elsif flag?(:dragonfly) %}
  require "./dragonfly/futex"
{% elsif flag?(:freebsd) || flag?(:linux) || flag?(:openbsd) %}
  require "./unix/futex"
{% elsif flag?(:win32) %}
  require "./win32/futex"
{% else %}
  {% skip_file %}
{% end %}
