# frozen_string_literal: true

module OCC
  # All C11 keyword strings mapped to their token type symbol.
  KEYWORDS = {
    'auto'            => :kw_auto,
    'break'           => :kw_break,
    'case'            => :kw_case,
    'char'            => :kw_char,
    'const'           => :kw_const,
    'continue'        => :kw_continue,
    'default'         => :kw_default,
    'do'              => :kw_do,
    'double'          => :kw_double,
    'else'            => :kw_else,
    'enum'            => :kw_enum,
    'extern'          => :kw_extern,
    'float'           => :kw_float,
    'for'             => :kw_for,
    'goto'            => :kw_goto,
    'if'              => :kw_if,
    'inline'          => :kw_inline,
    'int'             => :kw_int,
    'long'            => :kw_long,
    'register'        => :kw_register,
    'restrict'        => :kw_restrict,
    'return'          => :kw_return,
    'short'           => :kw_short,
    'signed'          => :kw_signed,
    'sizeof'          => :kw_sizeof,
    'static'          => :kw_static,
    'struct'          => :kw_struct,
    'switch'          => :kw_switch,
    'typedef'         => :kw_typedef,
    'union'           => :kw_union,
    'unsigned'        => :kw_unsigned,
    'void'            => :kw_void,
    'volatile'        => :kw_volatile,
    'while'           => :kw_while,
    '_Alignas'        => :kw__Alignas,
    '_Alignof'        => :kw__Alignof,
    '_Atomic'         => :kw__Atomic,
    '_Bool'           => :kw__Bool,
    '_Complex'        => :kw__Complex,
    '_Generic'        => :kw__Generic,
    '_Imaginary'      => :kw__Imaginary,
    '_Noreturn'       => :kw__Noreturn,
    '_Static_assert'  => :kw__Static_assert,
    '_Thread_local'   => :kw__Thread_local
  }.freeze

  # A single lexical token.
  Token = Struct.new(:type, :value, :location) do
    def keyword? = type.to_s.start_with?('kw_')
    def literal?  = %i[int_lit float_lit char_lit string_lit].include?(type)
    def eof?      = type == :eof

    def to_s
      case type
      when :eof        then 'EOF'
      when :int_lit    then "int(#{value[:raw]})"
      when :float_lit  then "float(#{value[:raw]})"
      when :char_lit   then "char(#{value[:value].inspect})"
      when :string_lit then "string(#{value[:value].inspect})"
      when :ident      then "ident(#{value})"
      else "#{type}(#{value})"
      end
    end
  end
end
