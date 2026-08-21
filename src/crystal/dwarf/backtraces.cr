module Crystal
  module DWARF
    class Backtraces
      property debug_abbrev : Bytes?
      property debug_info : Bytes?
      property debug_line : Bytes?
      property debug_line_str : Bytes?
      property debug_str : Bytes?

      # index to each individual abbreviation at an abbrev offset, so we don't have
      # to scan debug_abbrev over and over again to find the abbreviations we're
      # looking for, we can directly pinpoint the abbrev we need
      @abbrev_indexes = Hash(UInt64, Array(Int32)).new

      # the decoded table for resolving function names; parsed once from the
      # debug info and debug abbrev sections; the table is much smaller than the
      # sections (that has lots of debug into we don't need), and much faster to
      # search through
      #
      # OPTIMIZE: reduce the table row size, for example using offsets (u32)
      # instead of absolute PCs (u64).
      @function_names = Slice({UInt64, UInt64, UInt8*}).empty

      # Unlike function names we can't build a complete decompressed table as it
      # would quickly allocate several megabytes of memory. Instead, we build an
      # index of offsets and line registers to quickly find a sub-section and
      # resume the iteration.
      @line_numbers = Slice({Line::Registers, Int32, Int32}).empty

      @initialized = false

      def build_caches : Nil
        fn_time = nil
        ln_time = nil

        total = Time.measure do
          if ENV.has_key?("dw_cache_functions")
            fn_time = Time.measure { preload_function_names }
          else
            build_abbrev_indexes
          end

          if ENV.has_key?("dw_index_lines")
            ln_time = Time.measure { preload_line_numbers }
          end
        end

        if ENV.has_key?("dw_stats")
          print ".debug_abbrev bytesize=#{@debug_abbrev.try &.bytesize}\n"
          print ".debug_info bytesize=#{@debug_info.try &.bytesize}\n"
          print ".debug_line bytesize=#{@debug_line.try &.bytesize}\n"
          print ".debug_line_str bytesize=#{@debug_line_str.try &.bytesize}\n"
          print ".debug_str bytesize=#{@debug_line.try &.bytesize}\n"
          print "DW_function_cache size=#{@function_names.size} bytesize=#{@function_names.bytesize} time=#{fn_time.try &.to_microseconds}us\n"
          print "DW_line_index size=#{@line_numbers.size} bytesize=#{@line_numbers.bytesize} time=#{ln_time.try &.to_microseconds}us\n"
          print "DW_preload total_time=#{total.to_microseconds}us\n"
        end

        @initialized = true
      end

      # Cache individual offsets to each abbreviation into DEBUG_ABBREV for every
      # debug abbrev offset of DEBUG_INFO. Dramatically improves the performance
      # of looking up function names.
      private def build_abbrev_indexes : Nil
        return unless debug_abbrev = @debug_abbrev
        return unless debug_info = @debug_info

        Crystal::DWARF.each_info(debug_info) do |info|
          abbrev_table = debug_abbrev + info.debug_abbrev_offset
          @abbrev_indexes[info.debug_abbrev_offset] ||= parse_abbrev_indexes(abbrev_table)
        end
      end

      private def parse_abbrev_indexes(abbrev_table)
        Array(Int32).new.tap do |index|
          Crystal::DWARF.each_abbrev(abbrev_table) do |abbrev, offset|
            index << offset
            abbrev.each_attribute { }
          end
        end
      end

      private def preload_function_names : Nil
        return unless debug_info = @debug_info

        # use the length of the debug_info as the oversized mmap size; the
        # probability of the table being larger than the original debug info is
        # impossible
        table = memory_map(debug_info.bytesize, Tuple(UInt64, UInt64, UInt8*)) do |slice|
          size = 0
          abbrev_indexes = Hash(UInt64, Array(Int32)).new

          each_function_name_impl(abbrev_indexes) do |low_pc, high_pc, name_form, name_value|
            # strings are always null terminated, we save the pointer to reduce
            # the table's size (4/8 bytes instead of 8/16)
            cstring = decode_str(name_form, name_value).to_unsafe
            slice[size] = {low_pc, high_pc, cstring}
            size += 1
          end

          size
        end

        if table
          # while the low/high PC are mostly growing while following the debug
          # info, they actually aren't perfectly sorted in ascending order, we
          # must sort the table for binary searches
          @function_names = table.sort! do |a, b|
            cmp = a[0] <=> b[0]
            cmp == 0 ? a[1] <=> b[1] : cmp
          end
        end

        table
      end

      def lookup_function_name(pc : Int) : Bytes?
        if @function_names.empty?
          each_function_name do |low_pc, high_pc, name_form, name_value|
            if low_pc <= pc <= high_pc
              return decode_str(name_form, name_value)
            end
          end
        else
          bsearch_function_name(pc)
        end
      end

      def lookup_function_names(pcs : Enumerable(UInt64), &) : Nil
        return if pcs.empty?

        if @function_names.empty?
          found = pcs.size

          each_function_name do |low_pc, high_pc, name_form, name_value|
            pcs.each do |pc|
              if low_pc <= pc <= high_pc
                yield pc, decode_str(name_form, name_value)
                break if (found -= 1) == 0
              end
            end
          end
        else
          pcs.each do |pc|
            if bytes = bsearch_function_name(pc)
              yield pc, bytes
            end
          end
        end
      end

      private def bsearch_function_name(pc)
        a = @function_names
        l, r = 0, a.size

        while l < r
          m = l &+ (r &- l) // 2
          low_pc, high_pc, cstring = a.to_unsafe[m]

          if low_pc <= pc <= high_pc
            # found matching entry, abort
            return Bytes.new(cstring, LibC.strlen(cstring))
          end

          # leftmost binary search
          if low_pc < pc
            l = m &+ 1
          else
            r = m
          end
        end

        nil
      end

      def each_function_name(&) : Nil
        return unless @initialized

        each_function_name_impl(@abbrev_indexes) { |*args| yield(*args) }
      end

      private def each_function_name_impl(abbrev_indexes, &) : Nil
        return unless debug_abbrev = @debug_abbrev
        return unless debug_info = @debug_info

        DWARF.each_info(debug_info) do |info|
          abbrev_table = debug_abbrev + info.debug_abbrev_offset
          abbrev_index = abbrev_indexes[info.debug_abbrev_offset] ||= parse_abbrev_indexes(abbrev_table)

          info.each do |abbrev_code|
            offset = abbrev_index[abbrev_code &- 1]

            DWARF.abbrev_at(abbrev_table + offset) do |abbrev|
              if abbrev.tag == DW_TAG_subprogram
                low_pc = nil
                high_pc = nil
                name_form = nil
                name_value = nil

                abbrev.each_attribute do |attr|
                  value = info.read_attribute_value(attr.form, attr.const_value)

                  case attr.at
                  when DW_AT_low_pc
                    low_pc = value.as(LibC::SizeT)
                  when DW_AT_high_pc
                    if attr.form == DW_FORM_addr
                      high_pc = value.as(LibC::SizeT)
                    elsif value.responds_to?(:to_u64)
                      high_pc = low_pc.as(LibC::SizeT) + value.to_u64
                    end
                  when DW_AT_name
                    name_form = attr.form
                    name_value = value
                  end
                end

                if low_pc && high_pc && name_form && name_value
                  yield low_pc, high_pc, name_form, name_value
                end
              else
                abbrev.each_attribute do |attr|
                  info.skip_attribute_value(attr.form)
                end
              end
            end
          end
        end
      end

      private def preload_line_numbers : Nil
        return unless debug_line = @debug_line

        table = memory_map(debug_line.bytesize, Tuple(Line::Registers, Int32, Int32)) do |slice|
          size = 0

          DWARF.each_line_sequence(debug_line) do |sequence, sequence_offset|
            registers = Line::Registers.new(sequence.default_is_stmt)
            n = 0_u32

            sequence.read_statement_program(pointerof(registers)) do |offset|
              if (n & 127) == 0
                slice[size] = {registers, sequence_offset, offset}
                size += 1
              end
              n &+= 1
            end
          end

          size
        end

        @line_numbers = table if table
      end

      def lookup_line_number(pc : Int) : {Bytes, Bytes, UInt32, UInt32} | Nil
        if @line_numbers.empty?
          each_line_number do |sequence, low_pc, limit_pc, file_index, line, column|
            if low_pc <= pc < limit_pc
              directory, file = file_and_directory_at(sequence, file_index)
              return directory, file, line, column
            end
          end
        elsif i = bsearch_line_number_index(pc)
          resume_each_line_number(i) do |sequence, low_pc, limit_pc, file_index, line, column|
            if low_pc <= pc < limit_pc
              directory, file = file_and_directory_at(sequence, file_index)
              return directory, file, line, column
            end
          end
        end
      end

      private def bsearch_line_number_index(pc)
        a = @line_numbers
        l, r = 0, a.size

        while l < r
          m = l + (r - l) // 2
          addr = (a.to_unsafe + m).value[0].address

          # rightmost binary search
          if addr > pc
            r = m
          else
            l = m + 1
          end
        end

        r - 1 if r > 0
      end

      # NOTE: *pcs* MUST be sorted in ascending order.
      # NOTE: *pcs* SHOULD have unique values.
      def lookup_line_numbers(pcs : Array(UInt64), &) : Nil
        return if pcs.empty?
        offset = 0

        each_line_number do |sequence, low_pc, limit_pc, file_index, line, column|
          # PCs are sorted in ascending order, we only compare the first PCs
          # that may match, and skip any PC that has fallen behind (not found)
          pcs.each(within: offset..) do |pc|
            break if pc >= limit_pc

            if pc >= low_pc
              directory, file = file_and_directory_at(sequence, file_index)
              yield pc, directory, file, line, column
            end

            break if (offset += 1) == pcs.size
          end
        end
      end

      def each_line_number(&) : Nil
        return unless @initialized
        return unless debug_line = @debug_line

        # state of the previous entry in the matrix
        address = 0_u64
        file_index = 0_u32
        line = 0_u32
        column = 0_u32

        DWARF.each_line_sequence(debug_line) do |sequence|
          registers = Line::Registers.new(sequence.default_is_stmt)

          sequence.read_statement_program(pointerof(registers)) do
            unless address.zero?
              yield pointerof(sequence), address, registers.address, file_index, line, column
            end

            # save state
            address = registers.address
            file_index = registers.file
            line = registers.line
            column = registers.column
          end
        end
      end

      private def resume_each_line_number(i, &) : Nil
        return unless @initialized
        return unless debug_line = @debug_line

        registers, sequence_offset, program_offset = @line_numbers.to_unsafe[i]

        # record state
        address = registers.address
        file_index = registers.file
        line = registers.line
        column = registers.column

        i = -1
        DWARF.line_sequence_at(debug_line + sequence_offset) do |sequence|
          sequence.resume_statement_program(pointerof(registers), program_offset) do
            unless address.zero?
              yield pointerof(sequence), address, registers.address, file_index, line, column
            end

            # save state
            address = registers.address
            file_index = registers.file
            line = registers.line
            column = registers.column
          end
        end
      end

      private def file_and_directory_at(sequence, file_index)
        file = Bytes.empty
        directory = Bytes.empty
        directory_index = 0

        # must parse directories before we can parse files (skip)
        sequence.value.each_directory { }

        # files are 1-indexed
        i = 1
        sequence.value.each_file do |(form, value), dir_index, _, _, _|
          if i == file_index
            file = decode_str(form, value)
            directory_index = dir_index
            break
          end
          i += 1
        end

        unless file.empty?
          case directory_index
          when 0
            # special case
            directory = ".".to_slice
          else
            # re-parse the directories to get the file's directory
            sequence.value.rewind_headers

            # directories are 1-indexed
            i = 1
            sequence.value.each_directory do |(form, value)|
              if i == directory_index
                directory = decode_str(form, value)
                break
              end
              i += 1
            end
          end
        end

        {directory, file}
      end

      def decode_str(form, value)
        case form
        when DW_FORM_string
          value.as(Bytes)
        when DW_FORM_strp
          decode_strp(@debug_str, value.as(UInt8 | UInt16 | UInt32 | UInt64))
        when DW_FORM_line_strp
          decode_strp(@debug_line_str, value.as(UInt8 | UInt16 | UInt32 | UInt64))
        else
          Bytes.empty
        end
      end

      private def decode_strp(bytes, offset)
        if bytes && (0 <= offset < bytes.size)
          pointer = bytes.to_unsafe + offset
          bytesize = LibC.strlen(pointer).to_i32
          Bytes.new(pointer, bytesize, read_only: true)
        else
          Bytes.empty
        end
      end

      # The DWARF format doesn't give us any indication of how many entries
      # we're expecting and thus can't pre-allocate to the final size.
      #
      # We don't need to allocate in GC HEAP, the tables live until the program
      # terminates and don't contain pointers to GC HEAP memory to retain, they
      # only point to map memory.
      #
      # Using an Array would lead to reallocate its internal buffer many times,
      # requiring much more memory than necessary (several MB vs a few hundred
      # KB) and lots of memcopy.
      #
      # Instead, we overallocate an anonymous memory map, let the caller fill
      # some of it, then:
      #
      # - on UNIX we unmap the overallocated memory to return the
      #   reserved VIRT memory — the RSS memory was never allocated,
      # - on Windows we must free the whole map, and duplicated the slice.
      private def memory_map(bytesize, type : F.class, &) forall F
        # align to page size
        page_size =
          {% if flag?(:win32) %}
            LibC.GetNativeSystemInfo(out system_info)
            system_info.dwPageSize.to_u64
          {% else %}
            LibC.sysconf(LibC::SC_PAGESIZE).to_u64
          {% end %}
        aligned_bytesize = (bytesize.to_u64 &+ (page_size &- 1)) & (&-page_size)

        pointer = Pointer(Void).null

        # allocate map
        # OPTIMIZE: commit memory to avoid page faults (?)
        {% if flag?(:win32) %}
          pointer = LibC.VirtualAlloc(nil, aligned_bytesize, LibC::MEM_RESERVE, LibC::PAGE_READWRITE)
          return if pointer.null?
        {% else %}
          pointer = LibC.mmap(nil, aligned_bytesize, LibC::PROT_READ | LibC::PROT_WRITE, LibC::MAP_PRIVATE | LibC::MAP_ANON, -1, 0)
          return if pointer == LibC::MAP_FAILED
        {% end %}

        # fill what's needed
        slice = Slice(F).new(pointer.as(F*), aligned_bytesize // sizeof(F))
        actual_size = yield slice

        # the final
        table = slice[0, actual_size]

        {% if flag?(:win32) %}
          # Windows: we can't release the overallocated virtual memory, we thus
          # duplicate the slice and free it completely
          table = table.dup
          LibC.VirtualFree(0, aligned_bytesize, LibC::MEM_DECOMMIT)
        {% else %}
          # UNIX: truncate the overallocated memory map to its actual size
          boundary = (pointer + actual_size * sizeof(F)).align_up(page_size)
          limit = pointer + aligned_bytesize
          oversize = limit - boundary
          LibC.munmap(boundary, oversize) unless oversize == 0
        {% end %}

        table
      end
    end
  end
end
