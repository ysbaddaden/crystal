{% skip_file unless flag?(:wasi) && !flag?(:wasip1) %}

require "./spec_helper"
require "../spec_helper"

describe Crystal::EventLoop::Wasi, tags: "network" do
  it "times out waiting for a datagram" do
    socket = UDPSocket.new
    socket.bind("127.0.0.1", 0)
    socket.read_timeout = 10.milliseconds
    expect_raises(IO::TimeoutError, "Read timed out") { socket.receive }
  ensure
    socket.try &.close
  end

  it "waits for socket readiness and times out without fibers" do
    TCPServer.open("127.0.0.1", 0) do |server|
      TCPSocket.open("127.0.0.1", server.local_address.port) do |client|
        server.accept do |peer|
          client.read_timeout = 10.milliseconds
          expect_raises(IO::TimeoutError, "Read timed out") { client.gets(1) }
          peer.write_bytes(42_u8)
          Crystal::EventLoop.current.wait_readable(client)
          client.read_byte.should eq(42_u8)
          Crystal::EventLoop.current.wait_writable(client)
          peer.close_write
          client.read_byte.should be_nil
        end
      end
    end
  end

  it "times out writing when the peer does not read" do
    TCPServer.open("127.0.0.1", 0) do |server|
      TCPSocket.open("127.0.0.1", server.local_address.port) do |client|
        server.accept do |peer|
          client.send_buffer_size = 4096
          peer.recv_buffer_size = 4096
          client.write_timeout = 10.milliseconds
          buffer = Bytes.new(4096)
          expect_raises(IO::TimeoutError, "Write timed out") do
            loop { client.write(buffer) }
          end
        end
      end
    end
  end

  it "emulates sendfile with absolute offsets and preserves the file position" do
    TCPServer.open("127.0.0.1", 0) do |server|
      TCPSocket.open("127.0.0.1", server.local_address.port) do |client|
        server.accept do |peer|
          File.open(datapath("test_file.txt")) do |file|
            file.pos = 3
            client.sendfile(file, 0, 11).should eq(11)
            file.pos.should eq(3)
            peer.gets(11).should eq("Hello World")
            client.sendfile(file, file.size, 11).should eq(0)
            client.sendfile(file, 0, 0).should eq(0)
          end
        end
      end
    end
  end
end
