# frozen_string_literal: true

require 'occ/error'
require 'occ/source_location'
require 'occ/token'
require 'occ/lexer'
require 'occ/ast'
require 'occ/parser'

RSpec.describe OCC::Parser do
  def parse(src)
    tokens = OCC::Lexer.new(src, '<test>').tokenize
    OCC::Parser.new(tokens).parse
  end

  def parse_ok(src)
    expect { parse(src) }.not_to raise_error
    parse(src)
  end

  # ── Top-level structure ───────────────────────────────────────────────────────

  describe 'translation unit' do
    it 'parses an empty file' do
      ast = parse_ok('')
      expect(ast).to be_a(OCC::AST::TranslationUnit)
      expect(ast.decls).to be_empty
    end

    it 'parses a minimal main function' do
      ast = parse_ok("int main(void) { return 0; }")
      expect(ast.decls.length).to eq(1)
      expect(ast.decls.first).to be_a(OCC::AST::FunctionDef)
    end
  end

  # ── Declarations ─────────────────────────────────────────────────────────────

  describe 'variable declarations' do
    it 'parses a simple int declaration' do
      ast = parse_ok('int x;')
      decl = ast.decls.first
      expect(decl).to be_a(OCC::AST::Declaration)
      expect(decl.declarators.first[:name]).to eq('x')
    end

    it 'parses a declaration with initialiser' do
      ast = parse_ok('int x = 42;')
      init = ast.decls.first.declarators.first[:init]
      expect(init).to be_a(OCC::AST::IntLiteral)
      expect(init.raw).to eq('42')
    end

    it 'parses multiple declarators' do
      ast = parse_ok('int a, b, c;')
      expect(ast.decls.first.declarators.length).to eq(3)
    end

    it 'parses a pointer declaration' do
      ast = parse_ok('int *p;')
      expect(ast.decls.first.declarators.first[:name]).to eq('p')
    end

    it 'parses an array declaration' do
      ast = parse_ok('int arr[10];')
      expect(ast.decls.first.declarators.first[:name]).to eq('arr')
    end

    it 'parses a typedef' do
      ast = parse_ok('typedef int MyInt; MyInt x;')
      expect(ast.decls.length).to eq(2)
    end

    it 'parses a struct declaration' do
      src = 'struct Point { int x; int y; };'
      ast = parse_ok(src)
      tag_decl = ast.decls.first.specifiers.tag_decl
      expect(tag_decl).to be_a(OCC::AST::StructSpec)
      expect(tag_decl.fields.length).to eq(2)
    end

    it 'parses an enum declaration' do
      ast = parse_ok('enum Color { RED, GREEN, BLUE };')
      tag_decl = ast.decls.first.specifiers.tag_decl
      expect(tag_decl).to be_a(OCC::AST::EnumSpec)
      expect(tag_decl.enumerators.length).to eq(3)
    end
  end

  # ── Function definitions ──────────────────────────────────────────────────────

  describe 'function definitions' do
    it 'parses a function with parameters' do
      ast = parse_ok('int add(int a, int b) { return a + b; }')
      fn = ast.decls.first
      expect(fn).to be_a(OCC::AST::FunctionDef)
      expect(fn.params[:params].length).to eq(2)
    end

    it 'parses a variadic function declaration' do
      ast = parse_ok('int printf(const char *fmt, ...);')
      expect(ast.decls.first).to be_a(OCC::AST::Declaration)
    end

    it 'parses a void function' do
      ast = parse_ok('void noop(void) { }')
      fn = ast.decls.first
      expect(fn).to be_a(OCC::AST::FunctionDef)
    end
  end

  # ── Statements ────────────────────────────────────────────────────────────────

  describe 'statements' do
    def body(src)
      fn = parse_ok("void f(void) { #{src} }").decls.first
      fn.body.items
    end

    it 'parses a return statement' do
      items = body('return 0;')
      expect(items.first).to be_a(OCC::AST::ReturnStmt)
    end

    it 'parses an if statement' do
      items = body('if (x) { } else { }')
      expect(items.first).to be_a(OCC::AST::IfStmt)
    end

    it 'parses a while loop' do
      items = body('while (1) { break; }')
      expect(items.first).to be_a(OCC::AST::WhileStmt)
    end

    it 'parses a for loop' do
      items = body('for (int i = 0; i < 10; i++) { }')
      expect(items.first).to be_a(OCC::AST::ForStmt)
    end

    it 'parses a do-while loop' do
      items = body('do { } while (0);')
      expect(items.first).to be_a(OCC::AST::DoWhileStmt)
    end

    it 'parses a switch statement' do
      items = body('switch (x) { case 1: break; default: break; }')
      expect(items.first).to be_a(OCC::AST::SwitchStmt)
    end

    it 'parses break and continue' do
      items = body('while (1) { break; continue; }')
      inner = items.first.body.items
      expect(inner[0]).to be_a(OCC::AST::BreakStmt)
      expect(inner[1]).to be_a(OCC::AST::ContinueStmt)
    end

    it 'parses goto and labels' do
      items = body('goto done; done: return;')
      expect(items[0]).to be_a(OCC::AST::GotoStmt)
      expect(items[1]).to be_a(OCC::AST::LabelStmt)
    end

    it 'parses an empty statement' do
      items = body(';')
      expect(items.first).to be_a(OCC::AST::ExprStmt)
    end
  end

  # ── Expressions ───────────────────────────────────────────────────────────────

  describe 'expressions' do
    def expr(src)
      items = parse_ok("void f(void){#{src};}").decls.first.body.items
      items.first.expr
    end

    it 'parses integer literal' do
      e = expr('42')
      expect(e).to be_a(OCC::AST::IntLiteral)
      expect(e.raw).to eq('42')
    end

    it 'parses float literal' do
      e = expr('3.14')
      expect(e).to be_a(OCC::AST::FloatLiteral)
    end

    it 'parses string literal' do
      e = expr('"hello"')
      expect(e).to be_a(OCC::AST::StringLiteral)
      expect(e.value).to eq('hello')
    end

    it 'parses adjacent string concatenation' do
      e = expr('"foo" "bar"')
      expect(e).to be_a(OCC::AST::StringLiteral)
      expect(e.value).to eq('foobar')
    end

    it 'parses char literal' do
      e = expr("'a'")
      expect(e).to be_a(OCC::AST::CharLiteral)
    end

    it 'parses binary arithmetic with correct precedence' do
      e = expr('1 + 2 * 3')
      expect(e).to be_a(OCC::AST::BinaryOp)
      expect(e.op).to eq(:plus)
      expect(e.right).to be_a(OCC::AST::BinaryOp)
      expect(e.right.op).to eq(:star)
    end

    it 'parses parentheses overriding precedence' do
      e = expr('(1 + 2) * 3')
      expect(e).to be_a(OCC::AST::BinaryOp)
      expect(e.op).to eq(:star)
      expect(e.left).to be_a(OCC::AST::BinaryOp)
    end

    it 'parses a function call' do
      e = expr('f(1, 2)')
      expect(e).to be_a(OCC::AST::CallExpr)
      expect(e.args.length).to eq(2)
    end

    it 'parses array indexing' do
      e = expr('a[0]')
      expect(e).to be_a(OCC::AST::IndexExpr)
    end

    it 'parses member access with dot' do
      e = expr('s.x')
      expect(e).to be_a(OCC::AST::MemberExpr)
      expect(e.arrow).to be false
    end

    it 'parses member access with arrow' do
      e = expr('p->x')
      expect(e).to be_a(OCC::AST::MemberExpr)
      expect(e.arrow).to be true
    end

    it 'parses prefix increment' do
      e = expr('++i')
      expect(e).to be_a(OCC::AST::UnaryOp)
      expect(e.op).to eq(:pre_inc)
    end

    it 'parses postfix increment' do
      e = expr('i++')
      expect(e).to be_a(OCC::AST::UnaryOp)
      expect(e.op).to eq(:post_inc)
    end

    it 'parses address-of' do
      e = expr('&x')
      expect(e).to be_a(OCC::AST::UnaryOp)
      expect(e.op).to eq(:addr_of)
    end

    it 'parses dereference' do
      e = expr('*p')
      expect(e).to be_a(OCC::AST::UnaryOp)
      expect(e.op).to eq(:deref)
    end

    it 'parses sizeof expression' do
      e = expr('sizeof x')
      expect(e).to be_a(OCC::AST::SizeofExpr)
    end

    it 'parses sizeof type' do
      e = expr('sizeof(int)')
      expect(e).to be_a(OCC::AST::SizeofType)
    end

    it 'parses ternary operator' do
      e = expr('a ? b : c')
      expect(e).to be_a(OCC::AST::TernaryOp)
    end

    it 'parses assignment' do
      e = expr('x = 1')
      expect(e).to be_a(OCC::AST::Assign)
      expect(e.op).to eq(:assign)
    end

    it 'parses compound assignment' do
      e = expr('x += 1')
      expect(e).to be_a(OCC::AST::Assign)
      expect(e.op).to eq(:plus_assign)
    end

    it 'parses cast expression' do
      e = expr('(int)3.14')
      expect(e).to be_a(OCC::AST::Cast)
    end

    it 'parses comma expression' do
      e = expr('a, b, c')
      expect(e).to be_a(OCC::AST::CommaExpr)
      expect(e.exprs.length).to eq(3)
    end
  end

  # ── Error cases ───────────────────────────────────────────────────────────────

  describe 'error handling' do
    it 'raises ParseError for mismatched braces' do
      expect { parse('int f() {') }.to raise_error(OCC::ParseError)
    end

    it 'raises ParseError for missing semicolon' do
      expect { parse('int x') }.to raise_error(OCC::ParseError)
    end

    it 'raises ParseError for unexpected token in expression' do
      expect { parse('void f(void){ @ }') }.to raise_error(OCC::LexError)
    end
  end

  # ── Static assert ─────────────────────────────────────────────────────────────

  describe '_Static_assert' do
    it 'parses a static assert' do
      ast = parse_ok('_Static_assert(1, "ok");')
      expect(ast.decls.first).to be_a(OCC::AST::StaticAssert)
    end
  end
end
