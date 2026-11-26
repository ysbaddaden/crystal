require "../../spec_helper"

describe "Semantic: array" do
  it "types array literal of int" do
    assert_type(%(require "array_literal"; [1, 2, 3]), inject_primitives: true) { array_of(int32) }
  end

  it "types array literal of union" do
    assert_type(%(require "array_literal"; [1, 2.5]), inject_primitives: true) { array_of(union_of int32, float64) }
  end

  it "types empty typed array literal of int32" do
    assert_type("[] of Int32") { array_of(int32) }
  end

  it "types non-empty typed array literal of int" do
    assert_type(%(require "array_literal"; [1, 2, 3] of Int32), inject_primitives: true) { array_of(int32) }
  end

  it "types non-empty typed array literal of int" do
    assert_type(%(require "array_literal"; [1, 2, 3] of Int8), inject_primitives: true) { array_of(int8) }
  end

  it "types array literal size correctly" do
    assert_type(%(require "array_literal"; [1].size), inject_primitives: true) { int32 }
  end

  it "assignment in array literal works (#3195)" do
    assert_type(%(require "array_literal"; [a = 1]; a), inject_primitives: true) { int32 }
  end

  it "types array literal with splats" do
    assert_type(%(require "array_splat"; [1, *{'a', 1}, 2.5]), inject_primitives: true) { array_of(union_of int32, char, float64) }
  end

  it "types array literal with splats (2)" do
    assert_type(%(require "array_splat"; [1, *{1, 'a'}, 2.5]), inject_primitives: true) { array_of(union_of int32, char, float64) }
  end

  it "types array literal of int with splats" do
    assert_type(%(require "array_splat"; [1, *{2_i8, 3_i8}, 4] of Int8), inject_primitives: true) { array_of(int8) }
  end
end
