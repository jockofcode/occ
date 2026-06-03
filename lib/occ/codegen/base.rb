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

      # Subclasses implement these:
      def emit_preamble         = nil
      def emit_string_constant(id, value) = nil
      def emit_global(name, g)  = nil
      def emit_function(func)   = nil
    end
  end
end
