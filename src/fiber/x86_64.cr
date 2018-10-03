{% skip_file unless flag?(:x86_64) %}

class Fiber
  # :nodoc:
  def makecontext(stack_ptr, fiber_main)
    # in x86-64, the context switch push/pop 6 registers + return address (left on the stack):
    @context.stack_top = (stack_ptr - 7).as(Void*)
    @context.resumable = 1

    stack_ptr[0] = fiber_main.pointer # %rbx: initial `resume` will `ret` to this address
    stack_ptr[-1] = self.as(Void*)    # %rdi: puts `self` as first argument to `fiber_main` initial `resume`
  end

  # :nodoc:
  @[NoInline]
  @[Naked]
  def self.swapcontext(current_context, new_context) : Nil
    asm("
      pushq %rdi          // push 1st argument (for initial resume)
      pushq %rbx          // push callee-saved registers on the stack
      pushq %rbp
      pushq %r12
      pushq %r13
      pushq %r14
      pushq %r15
      movq %rsp, 8($0)    // current_context.stack_top = SP
      movl $$1, 0($0)     // current_context.resumable = 1

      movl $$0, 0($1)     // new_context.resumable = 0
      movq 8($1), %rsp    // SP = new_context.stack_top
      popq %r15           // pop callee-saved registers from the stack
      popq %r14
      popq %r13
      popq %r12
      popq %rbp
      popq %rbx
      popq %rdi           // pop 1st argument (for initial resume)
        " :: "r"(current_context), "r"(new_context))
  end
end
