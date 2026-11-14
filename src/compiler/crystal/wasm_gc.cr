require "llvm/enums/opcode"

module Crystal::WasmGC
  # Wasm locals are invisible to Boehm. After optimization, spill values live
  # across calls into the linear stack, which libgc scans. Volatile stores keep
  # the backend from removing these otherwise unused copies. Reuse slots at each
  # call so dead values don't keep objects alive until the function returns.
  def self.run(mod : LLVM::Module) : Nil
    builder = mod.new_builder
    mod.functions.each do |function|
      blocks = function.basic_blocks.to_a
      next if blocks.empty?
      next if LibLLVM.get_enum_attribute_at_index(function, LLVM::AttributeIndex::FunctionIndex, LLVM::Attribute.kind_for(LLVM::Attribute::Naked))

      instructions = blocks.to_h { |block| {block, block.instructions.to_a} }
      roots = find_roots(function, instructions)
      next if roots.empty?

      live_out = compute_liveness(blocks, instructions, roots)
      calls = collect_call_roots(blocks, instructions, roots, live_out)
      next if calls.empty?

      spill_roots(builder, function, instructions[blocks.first].first, calls)
    end
  end

  private def self.find_roots(function, instructions)
    root_types = Hash(LLVM::Type, Bool).new { |hash, type| hash[type] = root_type?(type) }
    roots = Set(LLVM::Value).new
    function.params.each { |param| roots << param if root_types[param.type] }

    instructions.each_value do |values|
      values.each { |value| roots << value if root_types[value.type] }
    end

    # Addressable stack objects are already scanned. Inlined backtrace frames
    # can otherwise account for hundreds of redundant roots in a function.
    non_heap = Set(LLVM::Value).new

    instructions.each_value do |values|
      values.each { |value| non_heap << value if opcode(value).alloca? }
    end

    loop do
      changed = false
      instructions.each_value do |values|
        values.each do |value|
          unless non_heap.includes?(value)
            known = non_heap?(value, non_heap)
            changed = true if known && non_heap.add?(value)
          end
        end
      end
      break unless changed
    end

    roots.subtract(non_heap)
  end

  private def self.non_heap?(value, non_heap)
    case opcode(value)
    when .get_element_ptr?, .trunc?, .z_ext?, .s_ext?, .ptr_to_int?, .int_to_ptr?, .bit_cast?, .addr_space_cast?
      non_heap_operand?(LLVM::Value.new(LibLLVM.get_operand(value, 0)), non_heap)
    when .phi?
      LibLLVM.count_incoming(value).times.all? do |i|
        non_heap_operand?(LLVM::Value.new(LibLLVM.get_incoming_value(value, i)), non_heap)
      end
    when .select?
      non_heap_operand?(LLVM::Value.new(LibLLVM.get_operand(value, 1)), non_heap) &&
        non_heap_operand?(LLVM::Value.new(LibLLVM.get_operand(value, 2)), non_heap)
    else
      false
    end
  end

  private def self.non_heap_operand?(value, non_heap)
    value.constant? || non_heap.includes?(value)
  end

  private def self.compute_liveness(blocks, instructions, roots)
    uses = {} of LLVM::BasicBlock => Set(LLVM::Value)
    defs = {} of LLVM::BasicBlock => Set(LLVM::Value)
    live_in = {} of LLVM::BasicBlock => Set(LLVM::Value)
    live_out = {} of LLVM::BasicBlock => Set(LLVM::Value)
    successors = {} of LLVM::BasicBlock => Array(LLVM::BasicBlock)

    blocks.each do |block|
      used = Set(LLVM::Value).new
      defined = Set(LLVM::Value).new

      instructions[block].each do |value|
        unless opcode(value).phi?
          each_operand(value) do |operand|
            used << operand if roots.includes?(operand) && !defined.includes?(operand)
          end
        end
        defined << value if roots.includes?(value)
      end

      uses[block] = used
      defs[block] = defined
      live_in[block] = Set(LLVM::Value).new
      live_out[block] = Set(LLVM::Value).new
      term = instructions[block].last

      successors[block] = Array.new(LibLLVM.get_num_successors(term)) do |i|
        LLVM::BasicBlock.new(LibLLVM.get_successor(term, i))
      end
    end

    predecessors = blocks.to_h { |block| {block, [] of LLVM::BasicBlock} }
    edge_uses = {} of {LLVM::BasicBlock, LLVM::BasicBlock} => Set(LLVM::Value)

    blocks.each do |block|
      successors[block].each do |successor|
        predecessors[successor] << block
        edge_uses[{block, successor}] = phi_edge_uses(instructions[successor], block, roots)
      end
    end

    pending = blocks.dup
    queued = blocks.to_set

    while block = pending.pop?
      queued.delete(block)
      outgoing = Set(LLVM::Value).new

      successors[block].each do |successor|
        outgoing.concat(live_in[successor])
        outgoing.concat(edge_uses[{block, successor}])
      end

      incoming = uses[block] | (outgoing - defs[block])
      live_out[block] = outgoing
      next if incoming == live_in[block]

      live_in[block] = incoming

      predecessors[block].each do |predecessor|
        pending << predecessor if queued.add?(predecessor)
      end
    end

    live_out
  end

  private def self.phi_edge_uses(instructions, predecessor, roots)
    used = Set(LLVM::Value).new

    # Phi operands are uses on incoming edges, not in the phi's block.
    instructions.each do |value|
      break unless opcode(value).phi?

      LibLLVM.count_incoming(value).times do |i|
        if LibLLVM.get_incoming_block(value, i) == predecessor.to_unsafe
          incoming = LLVM::Value.new(LibLLVM.get_incoming_value(value, i))
          used << incoming if roots.includes?(incoming)
        end
      end
    end

    used
  end

  private def self.collect_call_roots(blocks, instructions, roots, live_out)
    calls = {} of LLVM::Value => Array(LLVM::Value)

    blocks.each do |block|
      live = live_out[block].dup

      instructions[block].reverse_each do |value|
        live.delete(value)

        unless opcode(value).phi?
          each_operand(value) do |operand|
            live << operand if roots.includes?(operand)
          end
        end

        calls[value] = live.to_a if collecting_call?(value)
      end
    end

    calls
  end

  private def self.spill_roots(builder, function, first_instruction, calls)
    # A pool per LLVM type avoids casts and preserves the alignment required by
    # aggregates. Its size is bounded by the maximum live set at any call.
    counts = {} of LLVM::Type => Int32
    used = {} of LLVM::Type => Int32

    calls.each_value do |values|
      used.clear
      values.each do |value|
        type = value.type
        used[type] = (used[type]? || 0) + 1
      end
      used.each do |type, count|
        counts[type] = Math.max(counts[type]? || 0, count)
      end
    end
    return if counts.empty?

    # Foreign code can call back into Crystal and collect. Keep our root frame
    # on the stack until the foreign call has returned, even when the target
    # enables WebAssembly tail calls.
    function.add_attribute("disable-tail-calls", value: "true")
    LibLLVM.position_builder_before(builder, first_instruction)

    slots = counts.to_h do |type, count|
      {type, Array.new(count) { builder.alloca(type, "gc_root") }}
    end

    calls.each do |call, values|
      LibLLVM.position_builder_before(builder, call)
      used.clear
      values.each do |value|
        type = value.type
        index = used[type]? || 0
        builder.store_volatile(value, slots[type][index])
        used[type] = index + 1
      end

      slots.each do |type, pool|
        index = used[type]? || 0
        while index < pool.size
          builder.store_volatile(type.null, pool[index])
          index += 1
        end
      end
    end
  end

  private def self.collecting_call?(value)
    case opcode(value)
    when .call?, .invoke?, .call_br?
      # LLVM intrinsics cannot allocate through GC or call Crystal callbacks.
      !LLVM::Value.new(LibLLVM.get_called_value(value)).name.starts_with?("llvm.")
    else
      false
    end
  end

  private def self.opcode(value)
    LibLLVM.get_instruction_opcode(value)
  end

  private def self.each_operand(value, &)
    LibLLVM.get_num_operands(value).times do |i|
      yield LLVM::Value.new(LibLLVM.get_operand(value, i))
    end
  end

  # Only retain pointer-typed values and aggregates containing pointers.
  # Integer addresses (including object_id) are not strong references.
  private def self.root_type?(type : LLVM::Type) : Bool
    case type.kind
    when .pointer?
      true
    when .struct?
      type.struct_element_types.any? { |element| root_type?(element) }
    when .array?, .vector?
      root_type?(type.element_type)
    else
      false
    end
  end
end
