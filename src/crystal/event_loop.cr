# require "./scheduler"
require "event"

module Crystal
  # :nodoc:
  class EventLoop
    @eb : Event::Base
    @dns_base : Event::DnsBase?
    @loop_fiber : Fiber

    protected def initialize
      @eb = Event::Base.new
      @loop_fiber = spawn(name: "evloop") { @eb.run_loop }
    end

    def resume : Nil
      @loop_fiber.resume
    end

    def after_fork : Nil
      @eb.reinit
    end

    def create_resume_event(fiber)
      @eb.new_event(-1, LibEvent2::EventFlags::None, fiber) do |s, flags, data|
        data.as(Fiber).resume
      end
    end

    def create_fd_read_event(io : IO::FileDescriptor, edge_triggered : Bool = false)
      flags = LibEvent2::EventFlags::Read
      flags |= LibEvent2::EventFlags::Persist | LibEvent2::EventFlags::ET if edge_triggered
      event = @eb.new_event(io.fd, flags, io) do |s, flags, data|
        fd_io = data.as(IO::FileDescriptor)
        if flags.includes?(LibEvent2::EventFlags::Read)
          fd_io.resume_read
        elsif flags.includes?(LibEvent2::EventFlags::Timeout)
          fd_io.resume_read(timed_out: true)
        end
      end
      event
    end

    def create_fd_read_event(sock : Socket, edge_triggered : Bool = false)
      flags = LibEvent2::EventFlags::Read
      flags |= LibEvent2::EventFlags::Persist | LibEvent2::EventFlags::ET if edge_triggered
      event = @eb.new_event(sock.fd, flags, sock) do |s, flags, data|
        sock_ref = data.as(Socket)
        if flags.includes?(LibEvent2::EventFlags::Read)
          sock_ref.resume_read
        elsif flags.includes?(LibEvent2::EventFlags::Timeout)
          sock_ref.resume_read(timed_out: true)
        end
      end
      event
    end

    def create_fd_write_event(io : IO::FileDescriptor, edge_triggered : Bool = false)
      flags = LibEvent2::EventFlags::Write
      flags |= LibEvent2::EventFlags::Persist | LibEvent2::EventFlags::ET if edge_triggered
      event = @eb.new_event(io.fd, flags, io) do |s, flags, data|
        fd_io = data.as(IO::FileDescriptor)
        if flags.includes?(LibEvent2::EventFlags::Write)
          fd_io.resume_write
        elsif flags.includes?(LibEvent2::EventFlags::Timeout)
          fd_io.resume_write(timed_out: true)
        end
      end
      event
    end

    def create_fd_write_event(sock : Socket, edge_triggered : Bool = false)
      flags = LibEvent2::EventFlags::Write
      flags |= LibEvent2::EventFlags::Persist | LibEvent2::EventFlags::ET if edge_triggered
      event = @eb.new_event(sock.fd, flags, sock) do |s, flags, data|
        sock_ref = data.as(Socket)
        if flags.includes?(LibEvent2::EventFlags::Write)
          sock_ref.resume_write
        elsif flags.includes?(LibEvent2::EventFlags::Timeout)
          sock_ref.resume_write(timed_out: true)
        end
      end
      event
    end

    def create_dns_request(nodename, servname, hints, data, &callback : LibEvent2::DnsGetAddrinfoCallback)
      dns_base.getaddrinfo(nodename, servname, hints, data, &callback)
    end

    private def dns_base
      @dns_base ||= @eb.new_dns_base
    end
  end

  def self.event_loop : EventLoop
    @@event_loop ||= EventLoop.new
  end
end
