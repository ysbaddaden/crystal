require "../../spec_helper"

describe "Code gen: exception" do
  it "codegens rescue specific leaf exception" do
    link_and_run(<<-CRYSTAL).status.exit_code.should eq(2)
      require "compiler_spec_prelude/raise"

      class Foo < Exception
      end

      def foo
        raise Foo.new
      end

      def bar(x)
        2
      end

      result = begin
        foo
        3
      rescue ex : Foo
        bar(ex)
      end

      LibC.exit(result)
      CRYSTAL
  end

  it "codegens exception handler with return" do
    run(<<-CRYSTAL).to_i.should eq(1)
      require "compiler_spec_prelude/exceptions"

      def foo
        begin
          return 1
        ensure
          1 + 2
        end
      end

      foo
      CRYSTAL
  end

  it "does ensure after rescue which returns (#171)" do
    link_and_run(<<-CRYSTAL).status.exit_code.should eq(2)
      require "compiler_spec_prelude/raise"

      class Global
        @@x = 0

        def self.x=(@@x)
        end

        def self.x
          @@x
        end
      end

      def foo
        raise "foo"
      rescue
        Global.x += 1
        return
      ensure
        Global.x += 1
      end

      foo

      LibC.exit(Global.x)
      CRYSTAL
  end

  it "executes body if nothing raised (1)" do
    run(<<-CRYSTAL).to_i.should eq(3)
      require "compiler_spec_prelude/exceptions"

      y = 1
      x = begin
            2
          rescue
            y = 10
          end
      x + y
      CRYSTAL
  end

  it "executes rescue if something is raised conditionally" do
    link_and_run(<<-CRYSTAL).status.exit_code.should eq(8)
      require "compiler_spec_prelude/raise"
      y = 1
      x = 1

      x = begin
            y == 1 ? raise("Oh no!") : nil
            y = 10
          rescue
            y = 4
          end
      LibC.exit(x + y)
      CRYSTAL
  end

  it "executes rescue if something is raised unconditionally" do
    link_and_run(<<-CRYSTAL).status.exit_code.should eq(6)
      require "compiler_spec_prelude/raise"

      y = 1
      x = 1
      x = begin
            raise "Oh no!"
            y = 10
          rescue
            y = 3
          end
      LibC.exit(x + y)
      CRYSTAL
  end

  it "can result into union (1)" do
    run(<<-CRYSTAL).to_i.should eq(1)
      require "compiler_spec_prelude/exceptions"

      x = begin
            1
          rescue
            2.1
          end
      x.to_i
      CRYSTAL
  end

  it "can result into union (2)" do
    link_and_run(<<-CRYSTAL).status.exit_code.should eq(2)
      require "compiler_spec_prelude/raise"

      y = begin
            1 > 0 ? raise("Oh no!") : 0
          rescue
            2.1
          end
      LibC.exit(y.to_i)
      CRYSTAL
  end

  it "handles nested exceptions" do
    link_and_run(<<-CRYSTAL).status.exit_code.should eq(3)
      require "compiler_spec_prelude/raise"
      a = 0
      b = begin
            begin
              raise "Oh no!"
            rescue
              a = 1
              raise "Boom!"
            end
          rescue
            2
          end

      LibC.exit(a + b)
      CRYSTAL
  end

  it "executes ensure when no exception is raised (1)" do
    run(<<-CRYSTAL).to_i.should eq(10)
      require "compiler_spec_prelude/exceptions"

      a = 0
      b = begin
            a = 1
          rescue
            a = 3
          ensure
            a = 10
          end
      a
      CRYSTAL
  end

  it "executes ensure when no exception is raised (2)" do
    run(<<-CRYSTAL).to_i.should eq(1)
      require "compiler_spec_prelude/exceptions"

      a = 0
      b = begin
            a = 1
          rescue
            a = 3
          ensure
            a = 10
          end
      b
      CRYSTAL
  end

  it "executes ensure when exception is raised (1)" do
    link_and_run(<<-CRYSTAL).status.exit_code.should eq(2)
      require "compiler_spec_prelude/raise"

      a = 0
      b = begin
            a = 1
            raise "Oh no!"
          rescue
            a = 3
          ensure
            a = 2
          end
      LibC.exit(a)
      CRYSTAL
  end

  it "executes ensure when exception is raised (2)" do
    link_and_run(<<-CRYSTAL).status.exit_code.should eq(3)
      require "compiler_spec_prelude/raise"
      a = 0
      b = begin
            a = 1
            raise "Oh no!"
          rescue
            a = 3
          ensure
            a = 2
          end
      LibC.exit(b)
      CRYSTAL
  end

  it "executes ensure when exception is unhandled (1)" do
    link_and_run(<<-CRYSTAL).status.exit_code.should eq(3)
      require "compiler_spec_prelude/raise"

      class Ex1 < Exception; end

      a = 0
      b = begin
            begin
              a = 1
              raise "Oh no!"
            rescue Ex1
              a = 2
            ensure
              a = 3
            end
          rescue
            4
          end
      LibC.exit(a)
      CRYSTAL
  end

  it "executes ensure when exception is unhandled (2)" do
    link_and_run(<<-CRYSTAL).status.exit_code.should eq(4)
      require "compiler_spec_prelude/raise"

      class Ex1 < Exception; end

      a = 0
      b = begin
            begin
              a = 1
              raise "Oh no!"
            rescue Ex1
              a = 2
            ensure
              a = 3
            end
          rescue
            4
          end
      LibC.exit(b)
      CRYSTAL
  end

  it "ensure without rescue" do
    link_and_run(<<-CRYSTAL).status.exit_code.should eq(1)
      require "compiler_spec_prelude/raise"

      a = 0
      begin
        begin
          raise "Oh no!"
        ensure
          a = 1
        end
      rescue
      end

      LibC.exit(a)
      CRYSTAL
  end

  it "executes ensure when the main block returns" do
    run(<<-CRYSTAL).to_i.should eq(0)
      require "compiler_spec_prelude/exceptions"

      struct Nil; def to_i; 0; end; end

      def foo(x)
        begin
          return 0 if 1 == 1
        ensure
          x.value = 1
        end
      end

      x = 0
      foo(pointerof(x)).to_i
      CRYSTAL
  end

  it "executes ensure when the main block returns" do
    run(<<-CRYSTAL).to_i.should eq(1)
      require "compiler_spec_prelude/exceptions"

      def foo(x)
        begin
          return 0 if 1 == 1
        ensure
          x.value = 1
        end
      end

      x = 0
      foo(pointerof(x))
      x
      CRYSTAL
  end

  it "executes ensure when the main block yields and returns" do
    run(<<-CRYSTAL).to_i.should eq(1)
      require "compiler_spec_prelude/exceptions"

      def foo2(x)
        begin
          yield
        ensure
          x.value = 1
        end
      end

      def bar2(y)
        foo2(y) do
          return if 1 == 1
        end
      end

      x = 0
      bar2(pointerof(x))
      x
      CRYSTAL
  end

  it "rescues with type" do
    link_and_run(<<-CRYSTAL).status.exit_code.should eq(2)
      require "compiler_spec_prelude/raise"

      class Ex1 < Exception; end
      class Ex2 < Exception; end

      a = begin
            raise Ex2.new
          rescue Ex1
            1
          rescue Ex2
            2
          end

      LibC.exit(a)
      CRYSTAL
  end

  it "rescues with types defaults to generic rescue" do
    link_and_run(<<-CRYSTAL).status.exit_code.should eq(3)
      require "compiler_spec_prelude/raise"

      class Ex1 < Exception; end
      class Ex2 < Exception; end

      a = begin
            raise "Oh no!"
          rescue Ex1
            1
          rescue Ex2
            2
          rescue
            3
          end

      LibC.exit(a)
      CRYSTAL
  end

  it "handles exception in outer block (1)" do
    link_and_run(<<-CRYSTAL).status.exit_code.should eq(2)
      require "compiler_spec_prelude/raise"

      class Ex1 < Exception; end
      class Ex2 < Exception; end

      p = 0
      x = begin
            begin
              raise Ex1.new
            rescue Ex2
              p = 1
              1
            end
          rescue
            2
          end

      LibC.exit(x)
      CRYSTAL
  end

  it "handles exception in outer block (2)" do
    link_and_run(<<-CRYSTAL).status.exit_code.should eq(0)
      require "compiler_spec_prelude/raise"

      class Ex1 < Exception; end
      class Ex2 < Exception; end

      p = 0
      x = begin
            begin
              raise Ex1.new
            rescue Ex2
              p = 1
              1
            end
          rescue
            2
          end

      LibC.exit(p)
      CRYSTAL
  end

  it "handles subclass" do
    link_and_run(<<-CRYSTAL).status.exit_code.should eq(1)
      require "compiler_spec_prelude/raise"

      class Ex1 < Exception; end
      class Ex2 < Exception; end
      class Ex3 < Ex1; end

      x = 0
      begin
        raise Ex3.new
      rescue Ex1
        x = 1
      end
      LibC.exit(x)
      CRYSTAL
  end

  it "handle multiple exception types (1)" do
    link_and_run(<<-CRYSTAL).status.exit_code.should eq(1)
      require "compiler_spec_prelude/raise"

      class Ex1 < Exception; end
      class Ex2 < Exception; end

      x = 0
      begin
        raise Ex2.new
      rescue Ex1 | Ex2
        x = 1
      end
      LibC.exit(x)
      CRYSTAL
  end

  it "handle multiple exception types (2)" do
    link_and_run(<<-CRYSTAL).status.exit_code.should eq(1)
      require "compiler_spec_prelude/raise"

      class Ex1 < Exception; end
      class Ex2 < Exception; end

      x = 0
      begin
        raise Ex1.new
      rescue Ex1 | Ex2
        x = 1
      end
      LibC.exit(x)
      CRYSTAL
  end

  it "receives exception object" do
    result = link_and_run(<<-CRYSTAL)
      require "compiler_spec_prelude/class"
      require "compiler_spec_prelude/raise"

      class Ex1 < Exception
      end

      x = ""
      begin
        raise Ex1.new
      rescue ex
        x = ex.class.name
      end

      LibC.puts(x)
      CRYSTAL
    result.status.success?.should be_true
    result.output.should eq("Ex1\n")
  end

  it "executes else if no exception is raised (1)" do
    run(<<-CRYSTAL).to_i.should eq(3)
      require "compiler_spec_prelude/exceptions"

      x = 1
      y = begin
          rescue ex
            x = 2
          else
            x = 3
          end
      x
      CRYSTAL
  end

  it "executes else if no exception is raised (2)" do
    run(<<-CRYSTAL).to_i.should eq(3)
      require "compiler_spec_prelude/exceptions"

      x = 1
      y = begin
          rescue ex
            x = 2
          else
            x = 3
          end
      y
      CRYSTAL
  end

  it "doesn't execute else if exception is raised (1)" do
    link_and_run(<<-CRYSTAL).status.exit_code.should eq(2)
      require "compiler_spec_prelude/raise"

      class Ex1 < Exception; end

      x = 1
      y = begin
            raise Ex1.new
          rescue ex
            x = 2
          else
            x = 3
          end
      LibC.exit(x)
      CRYSTAL
  end

  it "doesn't execute else if exception is raised (2)" do
    link_and_run(<<-CRYSTAL).status.exit_code.should eq(2)
      require "compiler_spec_prelude/raise"

      class Ex1 < Exception; end

      x = 1
      y = begin
            raise Ex1.new
          rescue ex
            x = 2
          else
            x = 3
          end
      LibC.exit(y)
      CRYSTAL
  end

  it "doesn't execute else if exception is raised conditionally (1)" do
    link_and_run(<<-CRYSTAL).status.exit_code.should eq(2)
      require "compiler_spec_prelude/raise"

      class Ex1 < Exception; end

      x = 1
      y = begin
            raise Ex1.new if 1 == 1
          rescue ex
            x = 2
          else
            x = 3
          end
      LibC.exit(x)
      CRYSTAL
  end

  it "doesn't execute else if exception is raised conditionally (2)" do
    link_and_run(<<-CRYSTAL).status.exit_code.should eq(2)
      require "compiler_spec_prelude/raise"

      class Ex1 < Exception; end

      x = 1
      y = begin
            raise Ex1.new if 1 == 1
          rescue ex
            x = 2
          else
            x = 3
          end
      LibC.exit(y)
      CRYSTAL
  end

  it "handle exception raised by proc literal" do
    link_and_run(<<-CRYSTAL).status.exit_code.should eq(1)
      require "compiler_spec_prelude/raise"

      x = 0
      f = -> { raise "Foo" if 1 == 1 }
      begin
        f.call
      rescue
        x = 1
      end
      LibC.exit(x)
      CRYSTAL
  end

  it "codegens issue #118 (1)" do
    codegen(<<-CRYSTAL)
      require "compiler_spec_prelude/raise"

      begin
        raise "hey"
        n = 3
      ensure
        n
      end
      CRYSTAL
  end

  it "codegens issue #118 (2)" do
    codegen(<<-CRYSTAL)
      require "compiler_spec_prelude/raise"

      n = nil
      begin
        raise "hey"
        n = 3
      ensure
        n
      end
      CRYSTAL
  end

  it "captures exception thrown from proc" do
    link_and_run(<<-CRYSTAL).status.exit_code.should eq(2)
      require "compiler_spec_prelude/raise"

      def foo
        ->{ raise "OH NO" }.call
      end

      a = 1
      begin
        foo
      rescue
        a = 2
      end
      LibC.exit(a)
      CRYSTAL
  end

  it "uses exception after rescue" do
    result = link_and_run(<<-CRYSTAL)
      require "compiler_spec_prelude/raise"

      begin
        raise "OH NO"
      rescue ex
      end
      if ex && (message = ex.message)
        LibC.printf("%s", message)
      end
      CRYSTAL
    result.status.success?.should be_true
    result.output.should eq("OH NO")
  end

  it "doesn't codegen duplicated ensure if unreachable (#709)" do
    codegen(<<-CRYSTAL)
      require "compiler_spec_prelude/raise"

      class Foo
        def initialize
          LibC.exit(1) if 1 == 2
        end
      end

      begin
        begin
          while true
          end
        ensure
          Foo.new.object_id
        end
      ensure
      end
      CRYSTAL
  end

  it "executes ensure when raising inside rescue" do
    link_and_run(<<-CRYSTAL).status.exit_code.should eq(2)
      require "compiler_spec_prelude/raise"

      a = 1

      begin
        begin
          raise "OH NO"
        rescue
          raise "LALA"
        ensure
          a = 2
        end
      rescue
      end

      LibC.exit(a)
      CRYSTAL
  end

  it "executes ensure of break inside while inside body" do
    run(<<-CRYSTAL).to_i.should eq(123)
      require "compiler_spec_prelude/exceptions"

      a = 0
      while true
        begin
          break
        ensure
          a = 123
        end
      end
      a
      CRYSTAL
  end

  it "executes ensure of break inside while inside body with nested handlers" do
    run(<<-CRYSTAL).to_i.should eq(1)
      require "compiler_spec_prelude/exceptions"

      a = 0
      b = 0
      begin
        while true
          begin
            break
          ensure
            a += 1
          end
        end
        b = a
      ensure
        a += 1
      end
      b
      CRYSTAL
  end

  it "executes ensure of break inside while inside body with block" do
    run(<<-CRYSTAL).to_i.should eq(0)
      require "compiler_spec_prelude/exceptions"

      class Global
        @@a = 0
        @@b = 0

        def self.a=(@@a)
        end

        def self.a
          @@a
        end

        def self.b=(@@b)
        end

        def self.b
          @@b
        end
      end

      def bar
        begin
          yield
        ensure
          Global.a = 1
        end
      end

      bar do
        while true
          break
        end
        Global.b = Global.a
      end

      Global.b
      CRYSTAL
  end

  it "executes ensure of break inside while inside rescue" do
    link_and_run(<<-CRYSTAL).status.exit_code.should eq(123)
      require "compiler_spec_prelude/raise"

      a = 0
      while true
        begin
          raise "OH NO"
        rescue
          break
        ensure
          a = 123
        end
      end
      LibC.exit(a)
      CRYSTAL
  end

  it "executes ensure of break inside while inside else" do
    run(<<-CRYSTAL).to_i.should eq(123)
      require "compiler_spec_prelude/exceptions"

      a = 0
      while true
        begin
        rescue
        else
          break
        ensure
          a = 123
        end
      end
      a
      CRYSTAL
  end

  it "executes ensure of next inside while inside body" do
    run(<<-CRYSTAL).to_i.should eq(123)
      require "compiler_spec_prelude/exceptions"

      a = 0
      continue = true
      while continue
        continue = false
        begin
          next
        ensure
          a = 123
        end
      end
      a
      CRYSTAL
  end

  it "executes return inside rescue, executing ensure" do
    link_and_run(<<-CRYSTAL).status.exit_code.should eq(2)
      require "compiler_spec_prelude/raise"
      require "compiler_spec_prelude/once"

      class Global
        @@x = 0

        def self.x=(@@x)
        end

        def self.x
          @@x
        end
      end

      def foo
        begin
          begin
            raise "foo"
          rescue
            Global.x += 1
            return
          end
        ensure
          Global.x += 1
        end
      end

      foo

      LibC.exit(Global.x)
      CRYSTAL
  end

  it "executes ensure from return until target" do
    run(<<-CRYSTAL).to_i.should eq(1)
      require "compiler_spec_prelude/exceptions"

      def foo
        yield
        return
      end

      a = 0

      begin
        foo {}
      ensure
        a += 1
      end

      a
      CRYSTAL
  end

  it "executes ensure from return until target" do
    run(<<-CRYSTAL).to_i.should eq(2)
      require "compiler_spec_prelude/exceptions"

      class Global
        @@x = 0

        def self.x=(@@x)
        end

        def self.x
          @@x
        end
      end

      def foo
        begin
          yield
        ensure
          Global.x += 1
        end
      end

      def bar
        begin
          foo do
            return
          end
        ensure
          Global.x += 1
        end
      end

      bar

      Global.x
      CRYSTAL
  end

  it "executes ensure of next inside block" do
    run(<<-CRYSTAL).to_i.should eq(1)
      require "compiler_spec_prelude/exceptions"

      def foo
        yield
      end

      a = 0
      b = 0

      begin
        foo do
          begin
            next
          ensure
            a += 1
          end
        end
        b = a
      ensure
        a += 1
      end

      b
      CRYSTAL
  end

  it "executes ensure of next inside block" do
    run(<<-CRYSTAL).to_i.should eq(1)
      require "compiler_spec_prelude/exceptions"

      class Global
        @@a = 0
        @@b = 0

        def self.a=(@@a)
        end

        def self.a
          @@a
        end

        def self.b=(@@b)
        end

        def self.b
          @@b
        end
      end

      def foo
        begin
          yield
          Global.b = Global.a
        ensure
          Global.a += 1
        end
      end

      begin
        foo do
          begin
            next
          ensure
            Global.a += 1
          end
        end
      ensure
        Global.a += 1
      end

      Global.b
      CRYSTAL
  end

  it "executes ensure of break inside block" do
    run(<<-CRYSTAL).to_i.should eq(1)
      require "compiler_spec_prelude/exceptions"

      def foo
        yield
      end

      a = 0
      b = 0

      begin
        foo do
          begin
            break
          ensure
            a += 1
          end
        end
        b = a
      ensure
        a += 1
      end

      b
      CRYSTAL
  end

  it "executes ensure of calling method when doing break inside block (#1233)" do
    run(<<-CRYSTAL).to_i.should eq(123)
      require "compiler_spec_prelude/exceptions"

      class Global
        @@x = 0

        def self.x=(@@x)
        end

        def self.x
          @@x
        end
      end

      def foo
        yield
      ensure
        Global.x = 123
      end

      foo do
        break
      end

      Global.x
      CRYSTAL
  end

  it "propagates raise status (#2074)" do
    link_and_run(<<-CRYSTAL).status.exit_code.should eq(3)
      require "compiler_spec_prelude/raise"

      class Foo
        @var : Var?

        def method1
          method2
        end

        def method2
          if var = @var
            var.method3
          end
        end

        def var=(@var)
        end
      end

      class Var
        def method3
          raise "OH NO"
        end
      end

      # method1 isn't marked as raise because @var's type isn't known yet
      Foo.new.method1

      foo = Foo.new
      # This causes method2 to recompute, but method1 doesn't get notified
      # that it might now raise
      foo.var = Var.new
      a = 2
      begin
        foo.method1
      rescue ex
        a = 3
      end
      LibC.exit(a)
      CRYSTAL
  end

  it "doesn't crash on #1988" do
    link_and_run(<<-CRYSTAL).status.exit_code.should eq(42)
      require "compiler_spec_prelude/raise"

      begin
        x = 42
      rescue
      end

      rs = if x.is_a?(Int32)
             x
           else
             21
           end
      LibC.exit(rs)
      CRYSTAL
  end

  it "runs #2441" do
    result = link_and_run(<<-CRYSTAL)
      require "compiler_spec_prelude/raise"
      require "compiler_spec_prelude/string"

      while true
        begin
          raise "foo"
        rescue ex
          break
        end
      end

      if ex
        LibC.puts(ex.message || "")
      end
      CRYSTAL
    result.status.success?.should be_true
    result.output.should eq("foo\n")
  end

  it "can rescue TypeCastError (#2607)" do
    link_and_run(<<-CRYSTAL).status.exit_code.should eq(42)
      require "compiler_spec_prelude/raise"

      rs = begin
             (1 || "foo").as(String)
             41
           rescue e : TypeCastError
             42
           rescue e : Exception
             43
           end
      LibC.exit(rs)
      CRYSTAL
  end

  it "can use argument in rescue (#2844)" do
    result = link_and_run(<<-CRYSTAL)
      require "compiler_spec_prelude/raise"

      def foo(exe)
        begin
          raise exe
        rescue exe
          exe
        end
      end

      ex = Exception.new("foo")
      ex = foo(ex)
      LibC.puts(ex.message || "")
      CRYSTAL
    result.status.success?.should be_true
    result.output.should eq("foo\n")
  end

  it "can use argument in rescue, with a different type (1) (#2844)" do
    result = link_and_run(<<-CRYSTAL)
      require "compiler_spec_prelude/raise"

      def foo(exe)
        begin
          raise Exception.new("foo") if 1 == 1
          exe
        rescue exe
          exe
        end
      end

      ex = foo(1).as(Exception)
      LibC.puts(ex.message || "")
      CRYSTAL
    result.status.success?.should be_true
    result.output.should eq("foo\n")
  end

  it "can use argument in rescue, with a different type (2) (#2844)" do
    link_and_run(<<-CRYSTAL).status.exit_code.should eq(10)
      require "compiler_spec_prelude/raise"

      def foo(exe)
        begin
          raise Exception.new("foo") if 1 == 2
          exe
        rescue exe
          exe
        end
      end

      LibC.exit foo(10).as(Int32)
      CRYSTAL
  end

  it "runs NoReturn ensure (#3082)" do
    result = link_and_run(<<-CRYSTAL)
      require "compiler_spec_prelude/raise"

      begin
        LibC.printf "1"
        raise "OH NO"
        LibC.printf "0"
      rescue
        LibC.printf "2"
      ensure
        LibC.printf "3"
        LibC.exit(6)
        LibC.printf "4"
      end
      LibC.printf "5"
      CRYSTAL
    result.status.exit_code.should eq(6)
    result.output.should eq("123")
  end

  it "catches exception thrown by as inside method (#4030)" do
    result = link_and_run(<<-CRYSTAL)
      require "compiler_spec_prelude/raise"

      def foo
        a = 1 || ""
        a.as(String)
      end

      x = begin
            foo
            "bad"
          rescue ex : TypeCastError
            "good"
          end
      LibC.puts(x)
      CRYSTAL
    result.status.exit_code.should eq(0)
    result.output.should eq("good\n")
  end

  it "types parenthesized expression (#5511)" do
    result = link_and_run(<<-CRYSTAL)
      require "compiler_spec_prelude/raise"

      x = begin
            ((raise "foo").bar).baz
          rescue ex
            ex.message
          end
      LibC.puts(x || "")
      CRYSTAL
    result.status.exit_code.should eq(0)
    result.output.should eq("foo\n")
  end

  it "codegens return from rescue with value" do
    link_and_run(<<-CRYSTAL).status.exit_code.should eq(5)
      require "compiler_spec_prelude/raise"

      def foo
        begin
          raise "foo"
        rescue
          return 5
        end
      end

      LibC.exit(foo)
      CRYSTAL
  end

  it "closures rescue variable (#8141)" do
    codegen(<<-CRYSTAL)
      require "compiler_spec_prelude/exceptions"
      require "compiler_spec_prelude/proc"

      def invoke(&block)
        block.call
      end

      ex = nil

      invoke do
        begin
        rescue ex
        end
      end
      CRYSTAL
  end

  it "handles rescuing module type" do
    link_and_run(<<-CRYSTAL).status.exit_code.should eq(1)
      require "compiler_spec_prelude/raise"

      module Foo; end

      class Ex1 < Exception
        include Foo
      end

      x = 0
      begin
        raise Ex1.new
      rescue Foo
        x = 1
      end
      LibC.exit(x)
      CRYSTAL
  end

  it "handles rescuing union between module type and class type" do
    link_and_run(<<-CRYSTAL).status.exit_code.should eq(1)
      require "compiler_spec_prelude/raise"

      module Foo; end

      abstract class BaseError < Exception; end
      class Ex2 < BaseError; end

      class Ex1 < BaseError
        include Foo
      end

      x = 0
      begin
        raise Ex1.new
      rescue Foo | BaseError
        x = 1
      end
      LibC.exit(x)
      CRYSTAL
  end

  it "handles rescuing union between module types" do
    link_and_run(<<-CRYSTAL).status.exit_code.should eq(1)
      require "compiler_spec_prelude/raise"

      module Foo; end
      module Bar; end

      class Ex1 < Exception
        include Foo
      end

      class Ex2 < Exception
        include Bar
      end

      x = 0
      begin
        raise Ex1.new
      rescue Foo | Bar
        x = 1
      end
      LibC.exit(x)
      CRYSTAL
  end

  it "does not rescue just any module" do
    link_and_run(<<-CRYSTAL).status.exit_code.should eq(2)
      require "compiler_spec_prelude/raise"

      module Foo; end
      module Bar; end

      class Ex < Exception
        include Foo
      end

      x = 0
      begin
        begin
          raise Ex.new("oh no")
        rescue Bar
          x = 1
        end
      rescue ex
        x = 2
      end
      LibC.exit(x)
      CRYSTAL
  end

  it "rescues a valid union" do
    link_and_run(<<-CRYSTAL).status.exit_code.should eq(1)
      require "compiler_spec_prelude/raise"

      module Foo; end
      module Bar; end

      class Ex < Exception
        include Foo
      end

      x = 0
      begin
        raise Ex.new("oh no")
      rescue Union(Foo, Bar)
        x = 1
      end
      LibC.exit(x)
      CRYSTAL
  end

  it "rescues a valid nested union" do
    link_and_run(<<-CRYSTAL).status.exit_code.should eq(1)
      require "compiler_spec_prelude/raise"

      module Foo; end
      module Bar; end
      module Baz; end

      class Ex < Exception
        include Foo
      end

      x = 0
      begin
        raise Ex.new("oh no")
      rescue Union(Baz, Union(Foo, Bar))
        x = 1
      end
      LibC.exit(x)
      CRYSTAL
  end

  it "does not rescue just any union" do
    link_and_run(<<-CRYSTAL).status.exit_code.should eq(2)
      require "compiler_spec_prelude/raise"

      module Foo; end
      module Bar; end
      module Baz; end

      class Ex < Exception
        include Foo
      end

      x = 0
      begin
        raise Ex.new("oh no")
      rescue Union(Bar, Baz)
        x = 1
      rescue
        x = 2
      end
      LibC.exit(x)
      CRYSTAL
  end
end
