# frozen_string_literal: true

module OCC
  SourceLocation = Struct.new(:file, :line, :column) do
    def to_s
      "#{file}:#{line}:#{column}"
    end
  end
end
