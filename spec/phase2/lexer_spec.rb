# frozen_string_literal: true

require 'occ/token'
require 'occ/lexer'

RSpec.describe OCC::Lexer do
  def lex(src)
    OCC::Lexer.new(src, '<test>').tokenize
  end

  def types(src)
    lex(src).map(&:type)
  end

  # ── Keywords ────────────────────────────────────────────────────────────────

  describe 'keywords' do
    it 'recognises all C11 keywords' do
      keywords = %w[
        auto break case char const continue default do double else enum extern
        float for goto if inline int long register restrict return short signed
        sizeof static struct switch typedef union unsigned void volatile while
        _Alignas _Alignof _Atomic _Bool _Complex _Generic _Imaginary _Noreturn
        _Static_assert _Thread_local
      ]

      keywords.each do |kw|
        tokens = lex(kw)
        expect(tokens.first.type).to eq(:"kw_#{kw}"), "Expected #{kw} to be a keyword"
      end
    end

    it 'treats keyword-prefixed identifiers as identifiers' do
      tokens = lex('integer')
      expect(tokens.first.type).to eq(:ident)
      expect(tokens.first.value).to eq('integer')
    end
  end

  # ── Identifiers ─────────────────────────────────────────────────────────────

  describe 'identifiers' do
    it 'lexes a simple identifier' do
      t = lex('foo').first
      expect(t.type).to eq(:ident)
      expect(t.value).to eq('foo')
    end

    it 'lexes an identifier with leading underscore' do
      expect(lex('_bar').first.type).to eq(:ident)
    end

    it 'lexes an identifier with digits after the first char' do
      t = lex('x1y2').first
      expect(t.type).to eq(:ident)
      expect(t.value).to eq('x1y2')
    end
  end

  # ── Integer literals ─────────────────────────────────────────────────────────

  describe 'integer literals' do
    it 'lexes a decimal integer' do
      t = lex('42').first
      expect(t.type).to eq(:int_lit)
      expect(t.value[:raw]).to eq('42')
    end

    it 'lexes a hexadecimal integer' do
      t = lex('0xFF').first
      expect(t.type).to eq(:int_lit)
      expect(t.value[:raw]).to eq('0xFF')
    end

    it 'lexes an octal integer' do
      t = lex('0777').first
      expect(t.type).to eq(:int_lit)
      expect(t.value[:raw]).to eq('0777')
    end

    it 'lexes suffixed integers: u, l, ul, ll, ull' do
      %w[42u 42l 42ul 42ll 42ULL 42Lu].each do |lit|
        t = lex(lit).first
        expect(t.type).to eq(:int_lit), "Expected #{lit} to be int_lit"
        expect(t.value[:raw]).to eq(lit)
        expect(t.value[:suffix]).not_to be_empty
      end
    end

    it 'records the suffix separately' do
      t = lex('42ULL').first
      expect(t.value[:suffix]).to eq('ULL')
    end
  end

  # ── Float literals ────────────────────────────────────────────────────────────

  describe 'float literals' do
    it 'lexes a simple float' do
      t = lex('3.14').first
      expect(t.type).to eq(:float_lit)
    end

    it 'lexes a float with leading dot' do
      t = lex('.5').first
      expect(t.type).to eq(:float_lit)
    end

    it 'lexes a float with exponent' do
      t = lex('1.5e10').first
      expect(t.type).to eq(:float_lit)
    end

    it 'lexes a float with negative exponent' do
      t = lex('2.0E-3').first
      expect(t.type).to eq(:float_lit)
    end

    it 'lexes a float with f suffix' do
      t = lex('1.0f').first
      expect(t.type).to eq(:float_lit)
      expect(t.value[:suffix]).to eq('f')
    end

    it 'lexes a hex float' do
      t = lex('0x1.8p1').first
      expect(t.type).to eq(:float_lit)
    end
  end

  # ── String literals ───────────────────────────────────────────────────────────

  describe 'string literals' do
    it 'lexes a simple string' do
      t = lex('"hello"').first
      expect(t.type).to eq(:string_lit)
      expect(t.value[:value]).to eq('hello')
    end

    it 'lexes escape sequences in strings' do
      t = lex('"a\\nb"').first
      expect(t.value[:value]).to eq("a\nb")
    end

    it 'lexes a string with hex escape' do
      t = lex('"\\x41"').first
      expect(t.value[:value]).to eq('A')
    end

    it 'lexes a string with octal escape' do
      t = lex('"\\101"').first
      expect(t.value[:value]).to eq('A')
    end

    it 'lexes wide string L"..."' do
      t = lex('L"wide"').first
      expect(t.type).to eq(:string_lit)
      expect(t.value[:prefix]).to eq('L')
    end

    it 'lexes utf-8 string u8"..."' do
      t = lex('u8"utf"').first
      expect(t.type).to eq(:string_lit)
      expect(t.value[:prefix]).to eq('u8')
    end
  end

  # ── Character literals ────────────────────────────────────────────────────────

  describe 'character literals' do
    it 'lexes a plain char' do
      t = lex("'a'").first
      expect(t.type).to eq(:char_lit)
      expect(t.value[:value]).to eq('a')
    end

    it 'lexes an escape in a char literal' do
      t = lex("'\\n'").first
      expect(t.value[:value]).to eq("\n")
    end

    it 'lexes a wide char L\'...\'' do
      t = lex("L'x'").first
      expect(t.type).to eq(:char_lit)
      expect(t.value[:prefix]).to eq('L')
    end
  end

  # ── Operators and punctuators ────────────────────────────────────────────────

  describe 'operators and punctuators' do
    {
      '+'  => :plus,    '-'  => :minus,   '*'  => :star,    '/'  => :slash,
      '%'  => :percent, '&'  => :amp,     '|'  => :pipe,    '^'  => :caret,
      '~'  => :tilde,   '!'  => :exclaim, '='  => :assign,  '<'  => :lt,
      '>'  => :gt,      '?'  => :question,'('  => :lparen,  ')'  => :rparen,
      '['  => :lbracket,']'  => :rbracket,'{'  => :lbrace,  '}'  => :rbrace,
      ';'  => :semicolon,','=> :comma,    ':'  => :colon,   '.'  => :dot,
      '++' => :increment,'--'=> :decrement,'->'=> :arrow,   '...'=> :ellipsis,
      '==' => :eq,      '!=' => :neq,     '<=' => :leq,     '>=' => :geq,
      '&&' => :logical_and,'||'=> :logical_or,
      '<<' => :lshift,  '>>' => :rshift,
      '+=' => :plus_assign,'-=' => :minus_assign,
      '*=' => :star_assign, '/=' => :slash_assign,
      '%=' => :percent_assign,'&='=> :amp_assign,
      '|=' => :pipe_assign, '^=' => :caret_assign,
      '<<='=> :lshift_assign,'>>='=> :rshift_assign,
      '#'  => :hash,    '##' => :double_hash
    }.each do |src, expected_type|
      it "lexes '#{src}' as #{expected_type}" do
        t = lex(src).first
        expect(t.type).to eq(expected_type)
      end
    end
  end

  # ── Comments ──────────────────────────────────────────────────────────────────

  describe 'comments' do
    it 'skips line comments' do
      tokens = lex("// ignored\nint")
      expect(tokens.first.type).to eq(:kw_int)
    end

    it 'skips block comments' do
      tokens = lex('/* ignored */ int')
      expect(tokens.first.type).to eq(:kw_int)
    end

    it 'skips multi-line block comments' do
      tokens = lex("/* line1\nline2\n*/ int")
      expect(tokens.first.type).to eq(:kw_int)
    end

    it 'raises on unterminated block comment' do
      expect { lex('/* unterminated') }.to raise_error(OCC::LexError, /unterminated block comment/)
    end
  end

  # ── Source locations ─────────────────────────────────────────────────────────

  describe 'source locations' do
    it 'records the correct line and column for the first token' do
      t = lex('int').first
      expect(t.location.line).to eq(1)
      expect(t.location.column).to eq(1)
    end

    it 'advances line numbers correctly' do
      tokens = lex("int\nvoid")
      expect(tokens[1].location.line).to eq(2)
    end

    it 'advances column numbers correctly' do
      tokens = lex('int void')
      expect(tokens[1].location.column).to eq(5)
    end
  end

  # ── Line splicing ─────────────────────────────────────────────────────────────

  describe 'line splicing' do
    it 'joins lines split with backslash-newline' do
      tokens = lex("in\\\nt")
      expect(tokens.first.type).to eq(:kw_int)
    end
  end

  # ── EOF ───────────────────────────────────────────────────────────────────────

  describe 'EOF token' do
    it 'terminates the token stream with :eof' do
      tokens = lex('int x;')
      expect(tokens.last.type).to eq(:eof)
    end

    it 'produces exactly one :eof even for empty input' do
      tokens = lex('')
      expect(tokens.map(&:type)).to eq([:eof])
    end
  end

  # ── Error cases ───────────────────────────────────────────────────────────────

  describe 'error handling' do
    it 'raises LexError for unknown characters' do
      expect { lex('@') }.to raise_error(OCC::LexError, /unexpected character/)
    end

    it 'raises LexError for unterminated string literals' do
      expect { lex('"no closing') }.to raise_error(OCC::LexError, /unterminated string/)
    end

    it 'raises LexError for empty char literals' do
      expect { lex("''") }.to raise_error(OCC::LexError, /empty character/)
    end
  end
end
