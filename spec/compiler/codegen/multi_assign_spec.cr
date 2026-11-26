require "../../spec_helper"

describe "Code gen: multi assign" do
  it "supports n to n assignment" do
    run(<<-CRYSTAL).to_i.should eq(123)
      a, b, c = 1, 2, 3
      a &* 100 &+ b &* 10 &+ c
      CRYSTAL
  end

  context "without strict_multi_assign" do
    it "supports 1 to n assignment" do
      run(<<-CRYSTAL).to_i.should eq(123)
        class Foo
          def [](index)
            index &+ 1
          end
        end

        a, b, c = Foo.new
        a &* 100 &+ b &* 10 &+ c
        CRYSTAL
    end

    it "doesn't raise if value size in 1 to n assignment doesn't match target count" do
      run(<<-CRYSTAL).to_i.should eq(4)
        require "prelude"

        begin
          a, b = [1, 2, 3]
          4
        rescue ex : Exception
          raise ex unless ex.message == "Multiple assignment count mismatch"
          5
        end
        CRYSTAL
    end
  end

  context "strict_multi_assign" do
    it "supports 1 to n assignment" do
      run(<<-CRYSTAL, flags: %w(strict_multi_assign)).to_i.should eq(123)
        require "compiler_spec_prelude/exceptions"
        require "compiler_spec_prelude/range"
        require "compiler_spec_prelude/tuple"

        class Foo
          include Indexable(Int32)

          def unsafe_fetch(index)
            index &+ 1
          end

          def size
            3
          end
        end

        a, b, c = Foo.new
        a &* 100 &+ b &* 10 &+ c
        CRYSTAL
    end

    it "raises if value size in 1 to n assignment doesn't match target count" do
      run(<<-CRYSTAL, flags: %w(strict_multi_assign)).to_i.should eq(5)
        require "prelude"

        begin
          a, b = [1, 2, 3]
          4
        rescue ex : Exception
          raise ex unless ex.message == "Multiple assignment count mismatch"
          5
        end
        CRYSTAL
    end
  end

  it "supports m to n assignment, with splat on left-hand side (1)" do
    run(<<-CRYSTAL).to_i.should eq(12345)
      require "compiler_spec_prelude/tuple"

      a, *b, c = 1, 2, 3, 4, 5
      a &* 10000 &+ b[0] &* 1000 &+ b[1] &* 100 &+ b[2] &* 10 &+ c
      CRYSTAL
  end

  it "supports m to n assignment, with splat on left-hand side (2)" do
    run(<<-CRYSTAL).to_i.should eq(12345)
      require "compiler_spec_prelude/tuple"

      *a, b, c = 1, 2, 3, 4, 5
      a[0] &* 10000 &+ a[1] &* 1000 &+ a[2] &* 100 &+ b &* 10 &+ c
      CRYSTAL
  end

  it "supports m to n assignment, with splat on left-hand side (3)" do
    run(<<-CRYSTAL).to_i.should eq(12345)
      require "compiler_spec_prelude/tuple"

      a, b, *c = 1, 2, 3, 4, 5
      a &* 10000 &+ b &* 1000 &+ c[0] &* 100 &+ c[1] &* 10 &+ c[2]
      CRYSTAL
  end

  it "supports m to n assignment, splat is empty tuple (1)" do
    run(<<-CRYSTAL).to_b.should be_true
      require "compiler_spec_prelude/tuple"

      _, *x, _ = 1, 2
      x.is_a?(Tuple())
      CRYSTAL
  end

  it "supports m to n assignment, splat is empty tuple (2)" do
    run(<<-CRYSTAL).to_b.should be_true
      require "compiler_spec_prelude/tuple"

      *x, _, _ = 1, 2
      x.is_a?(Tuple())
      CRYSTAL
  end

  it "supports m to n assignment, splat is empty tuple (3)" do
    run(<<-CRYSTAL).to_b.should be_true
      require "compiler_spec_prelude/tuple"

      _, _, *x = 1, 2
      x.is_a?(Tuple())
      CRYSTAL
  end

  it "supports 1 to n assignment, with splat on left-hand side (1)" do
    run(<<-CRYSTAL).to_i.should eq(12345)
      require "compiler_spec_prelude/exceptions"
      require "compiler_spec_prelude/range"
      require "compiler_spec_prelude/tuple"

      a, *b, c = {1, 2, 3, 4, 5}
      a &* 10000 &+ b[0] &* 1000 &+ b[1] &* 100 &+ b[2] &* 10 &+ c
      CRYSTAL
  end

  it "supports 1 to n assignment, with splat on left-hand side (2)" do
    run(<<-CRYSTAL).to_i.should eq(12345)
      require "compiler_spec_prelude/range"
      require "compiler_spec_prelude/tuple"

      *a, b, c = {1, 2, 3, 4, 5}
      a[0] &* 10000 &+ a[1] &* 1000 &+ a[2] &* 100 &+ b &* 10 &+ c
      CRYSTAL
  end

  it "supports 1 to n assignment, with splat on left-hand side (3)" do
    run(<<-CRYSTAL).to_i.should eq(12345)
      require "compiler_spec_prelude/range"
      require "compiler_spec_prelude/tuple"

      a, b, *c = {1, 2, 3, 4, 5}
      a &* 10000 &+ b &* 1000 &+ c[0] &* 100 &+ c[1] &* 10 &+ c[2]
      CRYSTAL
  end

  it "supports 1 to n assignment, splat is empty (1)" do
    run(<<-CRYSTAL).to_b.should be_true
      require "compiler_spec_prelude/exceptions"
      require "compiler_spec_prelude/range"
      require "compiler_spec_prelude/tuple"

      _, *x, _ = {1, 2}
      x.is_a?(Tuple())
      CRYSTAL
  end

  it "supports 1 to n assignment, splat is empty (2)" do
    run(<<-CRYSTAL).to_b.should be_true
      require "compiler_spec_prelude/tuple"
      require "compiler_spec_prelude/range"

      *x, _, _ = {1, 2}
      x.is_a?(Tuple())
      CRYSTAL
  end

  it "supports 1 to n assignment, splat is empty (3)" do
    run(<<-CRYSTAL).to_b.should be_true
      require "compiler_spec_prelude/tuple"
      require "compiler_spec_prelude/range"

      _, _, *x = {1, 2}
      x.is_a?(Tuple())
      CRYSTAL
  end

  it "supports 1 to n assignment, raises if too short" do
    run(<<-CRYSTAL).to_b.should be_true
      require "prelude"

      begin
        a, *b, c = [1]
        false
      rescue ex : IndexError
        ex.message == "Multiple assignment count mismatch"
      end
      CRYSTAL
  end

  it "supports 1 to n assignment, raises if out of bounds (1)" do
    run(<<-CRYSTAL).to_b.should be_true
      require "prelude"

      begin
        *a, b, c = [1]
        false
      rescue ex : IndexError
        true
      end
      CRYSTAL
  end

  it "supports 1 to n assignment, raises if out of bounds (2)" do
    run(<<-CRYSTAL).to_b.should be_true
      require "prelude"

      begin
        a, b, *c = [1]
        false
      rescue ex : IndexError
        true
      end
      CRYSTAL
  end
end
