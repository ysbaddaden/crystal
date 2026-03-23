require "./codegen"

class Crystal::CodeGenVisitor
  # Calls __crystal_rwlock that takes a pointer to the value to protect (void*)
  # and returns a pointer to the associated rwlock object (void*).
  def rwlock(value_ptr)
    if func = main_fun?(RWLOCK)
      rwlock_ptr = alloca @llvm_context.void_pointer
      result = call func, [value_ptr]
      store result, rwlock_ptr
      rwlock_ptr
    end
  end

  # Calls __crystal_lock that takes a pointer to a rwlock object (void*).
  def lock(rwlock_ptr)
    if func = main_fun?(LOCK)
      tmp = load @llvm_context.void_pointer, rwlock_ptr
      call func, [tmp]
    end
  end

  # Calls __crystal_unlock that takes a pointer to a rwlock object (void*).
  def unlock(rwlock_ptr)
    if func = main_fun?(UNLOCK)
      tmp = load @llvm_context.void_pointer, rwlock_ptr
      call func, [tmp]
    end
  end

  # Calls __crystal_rlock that takes a pointer to a rwlock object (void*).
  def rlock(rwlock_ptr)
    if func = main_fun?(RLOCK)
      tmp = load @llvm_context.void_pointer, rwlock_ptr
      call func, [tmp]
    end
  end

  # Calls __crystal_runlock that takes a pointer to a rwlock object (void*).
  def runlock(rwlock_ptr)
    if func = main_fun?(RUNLOCK)
      tmp = load @llvm_context.void_pointer, rwlock_ptr
      call func, [tmp]
    end
  end
end
