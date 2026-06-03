# frozen_string_literal: true

require 'occ/error'
require 'occ/source_location'
require 'occ/token'
require 'occ/lexer'
require 'occ/ast'
require 'occ/parser'
require 'occ/types'
require 'occ/symbol_table'
require 'occ/semantic'

RSpec.describe OCC::Semantic do
  def analyze(src)
    tokens = OCC::Lexer.new(src, '<test>').tokenize
    ast    = OCC::Parser.new(tokens).parse
    sa     = OCC::Semantic.new
    sa.analyze(ast)
    sa
  end

  def errors_for(src)
    analyze(src).errors
  end

  def no_errors(src)
    errs = errors_for(src)
    expect(errs).to be_empty, "Expected no errors but got: #{errs.map(&:message).join(', ')}"
  end

  def has_error(src, pattern)
    errs = errors_for(src)
    expect(errs).not_to be_empty, "Expected an error matching #{pattern} but got none"
    expect(errs.map(&:message).join(' ')).to match(pattern)
  end

  # ── Valid programs ────────────────────────────────────────────────────────────

  describe 'valid programs' do
    it 'accepts a minimal main function' do
      no_errors('int main(void) { return 0; }')
    end

    it 'accepts variable declarations' do
      no_errors('int x; double y; char c;')
    end

    it 'accepts pointer declarations' do
      no_errors('int *p; char *s;')
    end

    it 'accepts arithmetic between compatible types' do
      no_errors('void f(void){ int x = 1; float y = 1.0f; }')
    end

    it 'accepts function calls with correct arity' do
      no_errors('int add(int a, int b){ return a + b; } void f(void){ add(1,2); }')
    end

    it 'accepts struct definitions and member access' do
      src = <<~C
        struct Point { int x; int y; };
        void f(void) {
          struct Point p;
          int v = p.x;
        }
      C
      no_errors(src)
    end

    it 'accepts typedef usage' do
      no_errors('typedef int MyInt; MyInt x = 42;')
    end

    it 'accepts string literals' do
      no_errors('void f(void){ const char *s = "hello"; }')
    end

    it 'accepts array access' do
      no_errors('void f(void){ int arr[10]; int v = arr[3]; }')
    end

    it 'accepts printf call' do
      no_errors('void f(void){ printf("hello %d\n", 42); }')
    end

    it 'accepts enum definitions' do
      no_errors('enum Color { RED, GREEN, BLUE }; int c = RED;')
    end
  end

  # ── Type checking errors ──────────────────────────────────────────────────────

  describe 'type errors' do
    it 'reports undeclared identifier' do
      has_error('void f(void){ int x = y; }', /undeclared identifier 'y'/)
    end

    it 'reports wrong number of arguments' do
      has_error('int add(int a, int b){ return a+b; } void f(void){ add(1); }',
                /wrong number of arguments/)
    end
  end

  # ── Type system ───────────────────────────────────────────────────────────────

  describe OCC::Types do
    describe 'usual arithmetic conversions' do
      it 'promotes int + int to int' do
        result = OCC::Types.usual_arithmetic_conversion(OCC::Types::INT, OCC::Types::INT)
        expect(result).to eq(OCC::Types::INT)
      end

      it 'promotes int + double to double' do
        result = OCC::Types.usual_arithmetic_conversion(OCC::Types::INT, OCC::Types::DOUBLE)
        expect(result).to eq(OCC::Types::DOUBLE)
      end

      it 'promotes int + long to long' do
        result = OCC::Types.usual_arithmetic_conversion(OCC::Types::INT, OCC::Types::LONG)
        expect(result).to eq(OCC::Types::LONG)
      end

      it 'promotes unsigned int + int to unsigned int' do
        result = OCC::Types.usual_arithmetic_conversion(OCC::Types::UINT, OCC::Types::INT)
        expect(result).to eq(OCC::Types::UINT)
      end
    end

    describe 'struct layout' do
      it 'computes correct offsets for a simple struct' do
        # Expected: a at 0, b at 4 (aligned to 4)
        st = OCC::Types::StructType.new(:kw_struct, 'test')
        st.fields = [
          { name: 'a', type: OCC::Types::CHAR, offset: 0 },
          { name: 'b', type: OCC::Types::INT,  offset: 4 }
        ]
        expect(st.fields[0][:offset]).to eq(0)
        expect(st.fields[1][:offset]).to eq(4)
      end

      it 'computes the correct size for a simple struct' do
        st = OCC::Types::StructType.new(:kw_struct, 'test')
        st.fields = [
          { name: 'a', type: OCC::Types::INT,  offset: 0 },
          { name: 'b', type: OCC::Types::INT,  offset: 4 }
        ]
        expect(st.size).to eq(8)
      end

      it 'computes correct size for a union' do
        ut = OCC::Types::StructType.new(:kw_union, 'u')
        ut.fields = [
          { name: 'i', type: OCC::Types::INT,  offset: 0 },
          { name: 'd', type: OCC::Types::DOUBLE, offset: 0 }
        ]
        expect(ut.size).to eq(8)
      end
    end

    describe 'type sizes and alignments' do
      {
        OCC::Types::CHAR      => [1, 1],
        OCC::Types::SHORT     => [2, 2],
        OCC::Types::INT       => [4, 4],
        OCC::Types::LONG      => [8, 8],
        OCC::Types::LONGLONG  => [8, 8],
        OCC::Types::FLOAT     => [4, 4],
        OCC::Types::DOUBLE    => [8, 8]
      }.each do |type, (sz, al)|
        it "#{type} has size=#{sz}, align=#{al}" do
          expect(type.size).to eq(sz)
          expect(type.align).to eq(al)
        end
      end
    end
  end
end
