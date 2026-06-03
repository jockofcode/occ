# frozen_string_literal: true

module OCC
  class Error < StandardError
    attr_reader :location

    def initialize(message, location = nil)
      @location = location
      prefix = location ? "#{location}: " : ''
      super("#{prefix}#{message}")
    end
  end

  class LexError      < Error; end
  class PreprocError  < Error; end
  class ParseError    < Error; end
  class SemanticError < Error; end
  class CodegenError  < Error; end
end
