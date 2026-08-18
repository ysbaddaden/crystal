require "crystal/dwarf"

struct Exception::CallStack
  @@dwarf = Crystal::DWARF::Backtraces.new

  protected def self.preload_dwarf_sections(program) : Nil
    program.section?(DEBUG_ABBREV) { |bytes, _| @@dwarf.debug_abbrev = bytes }
    program.section?(DEBUG_INFO) { |bytes, _| @@dwarf.debug_info = bytes }
    program.section?(DEBUG_LINE) { |bytes, _| @@dwarf.debug_line = bytes }
    program.section?(DEBUG_LINE_STR) { |bytes, _| @@dwarf.debug_line_str = bytes }
    program.section?(DEBUG_STR) { |bytes, _| @@dwarf.debug_str = bytes }
    @@dwarf.build_caches
  end

  protected def self.decode_line_number(pc)
    if result = @@dwarf.lookup_line_number(pc)
      directory, file, line, column = result
      unless directory.empty? && file.empty?
        return {dwarf_join(directory, file), line.to_i32, column.to_i32}
      end
    end
    {"??", 0, 0}
  end

  protected def self.decode_function_name(pc)
    if bytes = @@dwarf.lookup_function_name(pc)
      String.new(bytes)
    end
  end

  protected def self.decode_function_names(pcs : Enumerable(UInt64))
    Hash(UInt64, String).new(initial_capacity: pcs.size).tap do |result|
      @@dwarf.lookup_function_names(pcs) do |pc, bytes|
        result[pc] = String.new(bytes)
      end
    end
  end

  protected def self.decode_line_numbers(pcs : Enumerable(UInt64))
    Hash(UInt64, {String, Int32, Int32}).new(initial_capacity: pcs.size).tap do |result|
      @@dwarf.lookup_line_numbers(pcs) do |pc, directory, file, line, column|
        result[pc] = {dwarf_join(directory, file), line.to_i32, column.to_i32}
      end
    end
  end

  private def self.dwarf_join(directory, file)
    if directory.empty?
      String.new(file)
    else
      bytesize = directory.size + File::SEPARATOR_STRING.size + file.size
      String.build(bytesize) do |io|
        io.write(directory)
        io << File::SEPARATOR_STRING
        io.write(file)
      end
    end
  end
end
