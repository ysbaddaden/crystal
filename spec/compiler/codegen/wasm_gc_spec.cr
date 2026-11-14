require "../../spec_helper"

{% skip_file if LibLLVM::IS_LT_150 %}

private def wasm_gc_ir(source)
  with_tempfile("roots.ll") do |path|
    File.write(path, source)
    buffer = LLVM::MemoryBuffer.from_file(path)
    buffer.take_ownership { }
    mod = LLVM::Context.new.parse_ir(buffer)
    mod.verify
    Crystal::WasmGC.run(mod)
    mod.verify
    mod.to_s
  end
end

describe Crystal::WasmGC do
  it "spills pointers and pointer-containing aggregates, but not integer addresses" do
    ir = wasm_gc_ir <<-LLVM
      declare ptr @allocate()
      declare void @collect()
      declare void @consume(i32, ptr, { ptr, i32 })
      define ptr @example(ptr %arg, { ptr, i32 } %aggregate) {
      entry:
        %p = call ptr @allocate()
        %id = ptrtoint ptr %p to i32
        call void @collect()
        call void @consume(i32 %id, ptr %arg, { ptr, i32 } %aggregate)
        call void @collect()
        ret ptr %p
      }
      LLVM
    ir.should contain("alloca ptr")
    ir.should contain("store volatile ptr null")
    ir.should contain("store volatile ptr %arg")
    ir.should contain("store volatile ptr %p")
    ir.should_not contain("store volatile i32 %id")
    ir.should contain("store volatile { ptr, i32 } %aggregate")
    ir.should contain("\"disable-tail-calls\"=\"true\"")
  end

  it "does not spill integer-only values or aggregates" do
    ir = wasm_gc_ir <<-LLVM
      declare void @collect()
      declare void @consume(i32, i64, i128, { i32, [2 x i64] }, <4 x i32>)
      define void @example(i32 %small, i64 %large, i128 %wide, { i32, [2 x i64] } %aggregate, <4 x i32> %vector) {
      entry:
        call void @collect()
        call void @consume(i32 %small, i64 %large, i128 %wide, { i32, [2 x i64] } %aggregate, <4 x i32> %vector)
        ret void
      }
      LLVM
    ir.should_not contain("gc_root")
  end

  it "spills invoke results on the normal edge even when its destination has other predecessors" do
    ir = wasm_gc_ir <<-LLVM
      declare ptr @allocate()
      declare void @collect()
      declare i32 @personality(...)
      define ptr @example(i1 %condition) personality ptr @personality {
      entry:
        br i1 %condition, label %alloc, label %done
      alloc:
        %p = invoke ptr @allocate() to label %done unwind label %unwind
      done:
        %result = phi ptr [ null, %entry ], [ %p, %alloc ]
        call void @collect()
        ret ptr %result
      unwind:
        %exception = landingpad { ptr, i32 } cleanup
        call void @collect()
        resume { ptr, i32 } %exception
      }
      LLVM
    ir.should contain("store volatile ptr %result")
    ir.should contain("store volatile { ptr, i32 } %exception")
  end

  it "does not add stack slots to naked functions" do
    ir = wasm_gc_ir <<-LLVM
      define i32 @example(i32 %value) naked {
      entry:
        ret i32 42
      }
      LLVM
    ir.should_not contain("gc_root")
  end

  it "clears dead roots before a later collection" do
    ir = wasm_gc_ir <<-LLVM
      declare ptr @allocate()
      declare void @consume(ptr)
      declare void @collect()
      define void @example() {
      entry:
        %p = call ptr @allocate()
        call void @consume(ptr %p)
        call void @collect()
        ret void
      }
      LLVM
    ir.should match(/store volatile ptr %p, ptr %gc_root.*\n\s*call void @consume/)
    ir.should match(/store volatile ptr null, ptr %gc_root.*\n\s*call void @collect/)
    ir.scan(/gc_root\w* = alloca ptr/).size.should eq(1)
  end

  it "keeps roots live on loop backedges and exceptional paths" do
    ir = wasm_gc_ir <<-LLVM
      declare ptr @allocate()
      declare void @collect()
      declare i32 @personality(...)
      define ptr @example(ptr %arg, i1 %condition) personality ptr @personality {
      entry:
        br label %loop
      loop:
        %root = phi ptr [ %arg, %entry ], [ %next, %body ]
        invoke void @collect() to label %body unwind label %unwind
      body:
        %next = call ptr @allocate()
        br i1 %condition, label %loop, label %done
      done:
        ret ptr %root
      unwind:
        %exception = landingpad { ptr, i32 } cleanup
        ret ptr %root
      }
      LLVM
    ir.should match(/store volatile ptr %root, ptr %gc_root.*\n\s*invoke void @collect/)
    ir.should match(/store volatile ptr %root, ptr %gc_root.*\n\s*%next = call ptr @allocate/)
  end

  it "does not spill addresses of stack objects or static data" do
    ir = wasm_gc_ir <<-LLVM
      @data = global [2 x ptr] zeroinitializer
      declare void @consume(ptr, ptr)
      define void @example() {
      entry:
        %stack = alloca [2 x ptr]
        %element = getelementptr [2 x ptr], ptr %stack, i32 0, i32 1
        %global = getelementptr [2 x ptr], ptr @data, i32 0, i32 1
        call void @consume(ptr %element, ptr %global)
        ret void
      }
      LLVM
    ir.should_not contain("gc_root")
  end

  it "excludes stack-only selects but retains selects that can reference the heap" do
    ir = wasm_gc_ir <<-LLVM
      declare void @collect()
      declare void @consume(ptr, ptr)
      define void @example(ptr %heap, i1 %condition) {
      entry:
        %stack = alloca i32
        %local = select i1 %condition, ptr %stack, ptr null
        %mixed = select i1 %condition, ptr %stack, ptr %heap
        call void @collect()
        call void @consume(ptr %local, ptr %mixed)
        ret void
      }
      LLVM
    ir.should_not contain("store volatile ptr %local")
    ir.should contain("store volatile ptr %mixed")
  end

  it "does not spill roots at intrinsic calls" do
    ir = wasm_gc_ir <<-LLVM
      declare void @llvm.memset.p0.i32(ptr, i8, i32, i1)
      define void @example(ptr %arg) {
      entry:
        call void @llvm.memset.p0.i32(ptr %arg, i8 0, i32 8, i1 false)
        ret void
      }
      LLVM
    ir.should_not contain("gc_root")
  end
end
