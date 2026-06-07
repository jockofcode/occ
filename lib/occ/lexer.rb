# frozen_string_literal: true

module OCC
  class Lexer
    # String/char literal prefixes recognised by C11.
    STR_PREFIXES = %w[u8 u U L].freeze

    def initialize(source, filename = '<stdin>')
      @filename = filename
      # Splice physical lines: backslash-newline is removed before tokenising.
      @source = source.gsub(/\\\n/, '')
      @pos    = 0
      @line   = 1
      @col    = 1
    end

    # Returns an Array of Token, terminated by an :eof token.
    def tokenize
      tokens = []
      loop do
        skip_whitespace_and_comments
        break if at_end?
        tokens << scan_token
      end
      tokens << Token.new(:eof, nil, loc)
      tokens
    end

    private

    # ── Cursor helpers ──────────────────────────────────────────────────────

    def at_end? = @pos >= @source.length
    def cur      = @source[@pos]
    def peek(n = 1) = @source[@pos + n]
    def loc      = SourceLocation.new(@filename, @line, @col)

    def advance
      ch = @source[@pos]
      @pos += 1
      if ch == "\n"
        @line += 1
        @col = 1
      else
        @col += 1
      end
      ch
    end

    # Consume next character only if it matches +expected+.
    def match(expected)
      return false if at_end? || cur != expected
      advance
      true
    end

    # ── Whitespace / comment skipping ───────────────────────────────────────

    def skip_whitespace_and_comments
      loop do
        break if at_end?
        case cur
        when ' ', "\t", "\r", "\n"
          advance
        when '/'
          if peek == '/'
            advance while !at_end? && cur != "\n"
          elsif peek == '*'
            l = loc
            advance; advance   # consume /*
            loop do
              raise LexError.new('unterminated block comment', l) if at_end?
              if cur == '*' && peek == '/'
                advance; advance
                break
              end
              advance
            end
          else
            break
          end
        else
          break
        end
      end
    end

    # ── Top-level token dispatcher ──────────────────────────────────────────

    def scan_token
      l = loc

      # Check for string/char prefixes: L"", u"", U"", u8""
      if cur =~ /\A[LuU]\z/ && (peek == '"' || peek == "'")
        return scan_prefixed_literal(l)
      end
      if cur == 'u' && peek == '8' && (peek(2) == '"' || peek(2) == "'")
        return scan_prefixed_literal(l)
      end

      case cur
      when /[a-zA-Z_]/   then scan_ident_or_keyword(l)
      when /[0-9]/       then scan_number(l)
      when '.'
        if peek =~ /[0-9]/
          scan_number(l)
        elsif peek == '.' && peek(2) == '.'
          advance; advance; advance
          Token.new(:ellipsis, '...', l)
        else
          advance
          Token.new(:dot, '.', l)
        end
      when '"'  then scan_string_literal(l)
      when "'"  then scan_char_literal(l)
      when '+'
        advance
        if match('+') then Token.new(:increment,    '++', l)
        elsif match('=') then Token.new(:plus_assign, '+=', l)
        else Token.new(:plus, '+', l)
        end
      when '-'
        advance
        if match('-')    then Token.new(:decrement,    '--',  l)
        elsif match('=') then Token.new(:minus_assign, '-=',  l)
        elsif match('>') then Token.new(:arrow,        '->',  l)
        else Token.new(:minus, '-', l)
        end
      when '*'
        advance
        match('=') ? Token.new(:star_assign,    '*=', l) : Token.new(:star,    '*', l)
      when '/'
        advance
        match('=') ? Token.new(:slash_assign,   '/=', l) : Token.new(:slash,   '/', l)
      when '%'
        advance
        match('=') ? Token.new(:percent_assign, '%=', l) : Token.new(:percent, '%', l)
      when '&'
        advance
        if match('&')    then Token.new(:logical_and, '&&', l)
        elsif match('=') then Token.new(:amp_assign,  '&=', l)
        else Token.new(:amp, '&', l)
        end
      when '|'
        advance
        if match('|')    then Token.new(:logical_or,  '||', l)
        elsif match('=') then Token.new(:pipe_assign,  '|=', l)
        else Token.new(:pipe, '|', l)
        end
      when '^'
        advance
        match('=') ? Token.new(:caret_assign, '^=', l) : Token.new(:caret, '^', l)
      when '~'
        advance; Token.new(:tilde, '~', l)
      when '!'
        advance
        match('=') ? Token.new(:neq, '!=', l) : Token.new(:exclaim, '!', l)
      when '='
        advance
        match('=') ? Token.new(:eq, '==', l) : Token.new(:assign, '=', l)
      when '<'
        advance
        if match('<')
          match('=') ? Token.new(:lshift_assign, '<<=', l) : Token.new(:lshift, '<<', l)
        elsif match('=') then Token.new(:leq, '<=', l)
        else Token.new(:lt, '<', l)
        end
      when '>'
        advance
        if match('>')
          match('=') ? Token.new(:rshift_assign, '>>=', l) : Token.new(:rshift, '>>', l)
        elsif match('=') then Token.new(:geq, '>=', l)
        else Token.new(:gt, '>', l)
        end
      when '?'; advance; Token.new(:question,  '?', l)
      when ':'; advance; Token.new(:colon,     ':', l)
      when ';'; advance; Token.new(:semicolon, ';', l)
      when ','; advance; Token.new(:comma,     ',', l)
      when '('; advance; Token.new(:lparen,    '(', l)
      when ')'; advance; Token.new(:rparen,    ')', l)
      when '['; advance; Token.new(:lbracket,  '[', l)
      when ']'; advance; Token.new(:rbracket,  ']', l)
      when '{'; advance; Token.new(:lbrace,    '{', l)
      when '}'; advance; Token.new(:rbrace,    '}', l)
      when '#'
        advance
        match('#') ? Token.new(:double_hash, '##', l) : Token.new(:hash, '#', l)
      else
        ch = advance
        raise LexError.new("unexpected character '#{ch}'", l)
      end
    end

    # ── Identifier / keyword ─────────────────────────────────────────────────

    def scan_ident_or_keyword(l)
      start = @pos
      advance while !at_end? && cur =~ /[a-zA-Z0-9_]/
      text = @source[start...@pos]
      type = KEYWORDS[text] || :ident
      Token.new(type, text, l)
    end

    # ── String/char prefix (L, u, U, u8) ────────────────────────────────────

    def scan_prefixed_literal(l)
      prefix = ''
      prefix += advance                               # L / u / U
      prefix += advance if prefix == 'u' && cur == '8'
      cur == '"' ? scan_string_literal(l, prefix: prefix)
                 : scan_char_literal(l,   prefix: prefix)
    end

    # ── Numeric literals ─────────────────────────────────────────────────────

    def scan_number(l)
      start    = @pos
      is_float = false

      if cur == '0' && peek =~ /[xX]/
        # Hexadecimal integer or hex float
        advance; advance
        raise LexError.new('invalid hex literal', l) unless cur =~ /[0-9a-fA-F]/
        advance while !at_end? && cur =~ /[0-9a-fA-F]/
        if !at_end? && (cur == '.' || cur =~ /[pP]/)
          is_float = true
          advance if cur == '.'
          advance while !at_end? && cur =~ /[0-9a-fA-F]/
          if !at_end? && cur =~ /[pP]/
            advance
            advance if !at_end? && cur =~ /[+-]/
            raise LexError.new('hex float exponent has no digits', l) if at_end? || cur !~ /[0-9]/
            advance while !at_end? && cur =~ /[0-9]/
          end
        end
      elsif cur == '0' && !at_end? && peek =~ /[0-7]/
        # Octal
        advance
        advance while !at_end? && cur =~ /[0-7]/
      else
        # Decimal integer or decimal float
        advance while !at_end? && cur =~ /[0-9]/
        if !at_end? && (cur == '.' || cur =~ /[eE]/)
          is_float = true
          if cur == '.'
            advance
            advance while !at_end? && cur =~ /[0-9]/
          end
          if !at_end? && cur =~ /[eE]/
            advance
            advance if !at_end? && cur =~ /[+-]/
            raise LexError.new('exponent has no digits', l) if at_end? || cur !~ /[0-9]/
            advance while !at_end? && cur =~ /[0-9]/
          end
        end
      end

      # Collect suffix
      suffix = +''
      if is_float
        suffix << advance if !at_end? && cur =~ /[fFlL]/
      else
        while !at_end? && cur =~ /[uUlL]/
          suffix << advance
        end
      end

      raw  = @source[start...@pos]
      type = is_float ? :float_lit : :int_lit
      Token.new(type, { raw: raw, suffix: suffix }, l)
    end

    # ── String literal ───────────────────────────────────────────────────────

    def scan_string_literal(l, prefix: nil)
      advance   # consume opening "
      value = +''
      loop do
        raise LexError.new('unterminated string literal', l) if at_end? || cur == "\n"
        break if cur == '"'
        value << scan_escape_sequence
      end
      advance   # consume closing "
      Token.new(:string_lit, { value: value, prefix: prefix }, l)
    end

    # ── Character literal ────────────────────────────────────────────────────

    def scan_char_literal(l, prefix: nil)
      advance   # consume opening '
      raise LexError.new('empty character literal', l) if cur == "'"
      value = scan_escape_sequence
      raise LexError.new("multi-character literal (use double-quotes for strings)", l) if cur != "'"
      advance   # consume closing '
      Token.new(:char_lit, { value: value, prefix: prefix }, l)
    end

    # ── Escape sequence (shared by strings and chars) ────────────────────────

    def scan_escape_sequence
      return advance unless cur == '\\'

      advance   # consume backslash
      case cur
      when 'n'  then advance; "\n"
      when 't'  then advance; "\t"
      when 'r'  then advance; "\r"
      when 'a'  then advance; "\a"
      when 'b'  then advance; "\b"
      when 'f'  then advance; "\f"
      when 'v'  then advance; "\v"
      when '0'  then advance; "\0"
      when '\\' then advance; "\\"
      when "'"  then advance; "'"
      when '"'  then advance; '"'
      when '?'  then advance; '?'
      when 'x'
        advance
        hex = +''
        while !at_end? && cur =~ /[0-9a-fA-F]/
          hex << advance
        end
        raise LexError.new('empty hex escape sequence', loc) if hex.empty?
        hex.to_i(16).chr(Encoding::UTF_8) rescue hex.to_i(16).chr
      when 'u'
        advance
        hex = +''
        4.times { hex << advance if !at_end? && cur =~ /[0-9a-fA-F]/ }
        raise LexError.new('invalid \\u escape sequence', loc) if hex.length != 4
        [hex.to_i(16)].pack('U')
      when 'U'
        advance
        hex = +''
        8.times { hex << advance if !at_end? && cur =~ /[0-9a-fA-F]/ }
        raise LexError.new('invalid \\U escape sequence', loc) if hex.length != 8
        [hex.to_i(16)].pack('U')
      when /[0-7]/
        oct = +''
        3.times { oct << advance if !at_end? && cur =~ /[0-7]/ }
        oct.to_i(8).chr
      else
        ch = advance
        raise LexError.new("unknown escape sequence '\\#{ch}'", loc)
      end
    end
  end
end
