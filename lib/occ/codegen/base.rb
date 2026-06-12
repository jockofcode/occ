# frozen_string_literal: true

module OCC
  module Codegen
    # Common helpers shared by all backends.
    class Base
      def initialize(mod)
        @mod = mod
        @out = []
      end

      def generate
        emit_preamble
        @mod.strings.each_with_index { |s, i| emit_string_constant(i, s) }
        @mod.globals.each            { |name, g| emit_global(name, g) }
        @mod.functions.each          { |f| emit_function(f) }
        @out.join("\n")
      end

      private

      def emit(line) = @out << line
      def emit_blank  = @out << ''

      # Produce an assembler-quoted string literal from a Ruby string.
      # Uses octal escapes for non-printable / non-ASCII bytes so that GNU as
      # (and the macOS assembler) never sees unsupported \uXXXX sequences.
      def asm_string(s)
        result = +'"'
        s.each_byte do |b|
          result << case b
                    when 0x22 then '\\"'
                    when 0x5C then '\\\\'
                    when 0x0A then '\\n'
                    when 0x0D then '\\r'
                    when 0x09 then '\\t'
                    when 0x20..0x7E then b.chr
                    else format('\\%03o', b)
                    end
        end
        result << '"'
      end

      # Subclasses implement these:
      def emit_preamble         = nil
      def emit_string_constant(id, value) = nil
      def emit_global(name, g)  = nil
      def emit_function(func)   = nil
    end
  end
end
