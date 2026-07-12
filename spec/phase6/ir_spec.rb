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
require 'occ/ir'

RSpec.describe OCC::IR do
  def build_ir(src)
    tokens  = OCC::Lexer.new(src, '<test>').tokenize
    ast     = OCC::Parser.new(tokens).parse
    sa      = OCC::Semantic.new
    sa.analyze(ast)
    builder = OCC::IR::Builder.new
    builder.build(ast)
  end

  def function_named(mod, name)
    mod.functions.find { |f| f.name == name }
  end

  def all_instrs(func)
    func.blocks.flat_map(&:instrs)
  end

  # ── Module structure ──────────────────────────────────────────────────────────

  describe 'module' do
    it 'produces a module for an empty translation unit' do
      mod = build_ir('')
      expect(mod).to be_a(OCC::IR::Mod)
    end

    it 'adds a function for each function definition' do
      mod = build_ir('int f(void){ return 1; } int g(void){ return 2; }')
      expect(mod.functions.map(&:name)).to include('f', 'g')
    end
  end

  # ── Function structure ────────────────────────────────────────────────────────

  describe 'function' do
    it 'produces a non-empty block list' do
      mod  = build_ir('int main(void){ return 0; }')
      func = function_named(mod, 'main')
      expect(func.blocks).not_to be_empty
    end

    it 'entry block is the first block' do
      mod  = build_ir('int main(void){ return 0; }')
      func = function_named(mod, 'main')
      expect(func.entry_block.label).to eq('entry')
    end

    it 'every block is terminated' do
      mod  = build_ir('int main(void){ return 0; }')
      func = function_named(mod, 'main')
      func.blocks.each do |bb|
        expect(bb.terminated?).to be(true), "Block #{bb.label} is not terminated"
      end
    end
  end

  # ── Switch ───────────────────────────────────────────────────────────────────

  describe 'switch statement' do
    it 'collects case labels nested in a compound block directly under switch' do
      mod = build_ir(<<~C)
        enum { OP_END = 1, OP_EXACT1 = 2 };
        int f(unsigned char *p) {
          while (1) {
            switch (*p++) {
              {
                case OP_END: return 1;
                case OP_EXACT1: return 2;
              }
            }
          }
        }
      C
      func = function_named(mod, 'f')

      expect(func.blocks.map(&:label).grep(/\Aswitch_case/).length).to eq(2)
      expect(all_instrs(func).grep(OCC::IR::CondJump).length).to be >= 2
    end
  end

  # ── Return ────────────────────────────────────────────────────────────────────

  describe 'return statement' do
    it 'emits a Return instruction with the return value' do
      mod  = build_ir('int f(void){ return 42; }')
      func = function_named(mod, 'f')
      ret  = all_instrs(func).find { |i| i.is_a?(OCC::IR::Return) }
      expect(ret).not_to be_nil
      expect(ret.value).to be_a(OCC::IR::Const)
      expect(ret.value.value).to eq(42)
    end

    it 'emits a Return with no value for void return' do
      mod  = build_ir('void f(void){ return; }')
      func = function_named(mod, 'f')
      ret  = all_instrs(func).find { |i| i.is_a?(OCC::IR::Return) }
      expect(ret.value).to be_nil
    end
  end

  # ── Arithmetic ────────────────────────────────────────────────────────────────

  describe 'arithmetic expressions' do
    it 'emits a Binary instruction for addition' do
      mod  = build_ir('int f(void){ return 1 + 2; }')
      func = function_named(mod, 'f')
      bin  = all_instrs(func).find { |i| i.is_a?(OCC::IR::Binary) && i.op == :plus }
      expect(bin).not_to be_nil
      expect(bin.left).to be_a(OCC::IR::Const)
      expect(bin.right).to be_a(OCC::IR::Const)
    end

    it 'emits Binary instructions for nested arithmetic' do
      mod  = build_ir('int f(void){ return 1 + 2 * 3; }')
      func = function_named(mod, 'f')
      bins = all_instrs(func).select { |i| i.is_a?(OCC::IR::Binary) }
      expect(bins.length).to be >= 2
    end
  end

  # ── Local variables ───────────────────────────────────────────────────────────

  describe 'local variables' do
    it 'emits Alloca for each local variable' do
      mod  = build_ir('void f(void){ int x = 0; int y = 1; }')
      func = function_named(mod, 'f')
      allocas = all_instrs(func).select { |i| i.is_a?(OCC::IR::Alloca) }
      expect(allocas.length).to be >= 2
    end

    it 'emits Store when a variable is initialised' do
      mod  = build_ir('void f(void){ int x = 5; }')
      func = function_named(mod, 'f')
      stores = all_instrs(func).select { |i| i.is_a?(OCC::IR::Store) }
      expect(stores).not_to be_empty
    end

    it 'emits Load when a variable is read' do
      mod  = build_ir('int f(void){ int x = 5; return x; }')
      func = function_named(mod, 'f')
      loads = all_instrs(func).select { |i| i.is_a?(OCC::IR::Load) }
      expect(loads).not_to be_empty
    end

    it 'keeps stack slots for declarations after a terminator but before a label' do
      mod = build_ir(<<~C)
        extern long g(void);
        long f(int c) {
          if (c) goto slow;
          return 1;
          long v;
        slow:
          v = g();
          return v;
        }
      C
      func = function_named(mod, 'f')

      expect(all_instrs(func).grep(OCC::IR::Alloca).length).to be >= 2
      stores_to_alloca = all_instrs(func).grep(OCC::IR::Store).select { |i| i.ptr.is_a?(OCC::IR::Temp) }
      expect(stores_to_alloca).not_to be_empty
    end
  end

  # ── Control flow ──────────────────────────────────────────────────────────────

  describe 'if statement' do
    it 'emits CondJump for an if condition' do
      mod  = build_ir('void f(int x){ if (x) { } }')
      func = function_named(mod, 'f')
      cj   = all_instrs(func).find { |i| i.is_a?(OCC::IR::CondJump) }
      expect(cj).not_to be_nil
    end

    it 'produces separate then and end blocks' do
      mod  = build_ir('void f(int x){ if (x) { int y = 1; } }')
      func = function_named(mod, 'f')
      labels = func.blocks.map(&:label)
      expect(labels.any? { |l| l.start_with?('if_then') }).to be true
      expect(labels.any? { |l| l.start_with?('if_end') }).to be true
    end

    it 'produces else block when else branch exists' do
      mod  = build_ir('void f(int x){ if (x) { } else { } }')
      func = function_named(mod, 'f')
      labels = func.blocks.map(&:label)
      expect(labels.any? { |l| l.start_with?('if_else') }).to be true
    end
  end

  describe 'while loop' do
    it 'emits CondJump and produces loop blocks' do
      mod  = build_ir('void f(void){ int i = 0; while (i) { i = 0; } }')
      func = function_named(mod, 'f')
      labels = func.blocks.map(&:label)
      expect(labels.any? { |l| l.start_with?('while_cond') }).to be true
      expect(labels.any? { |l| l.start_with?('while_body') }).to be true
      expect(labels.any? { |l| l.start_with?('while_end') }).to be true
    end
  end

  describe 'for loop' do
    it 'produces for-loop blocks' do
      mod  = build_ir('void f(void){ for (int i=0; i; i++) { } }')
      func = function_named(mod, 'f')
      labels = func.blocks.map(&:label)
      expect(labels.any? { |l| l.start_with?('for_cond') }).to be true
      expect(labels.any? { |l| l.start_with?('for_body') }).to be true
      expect(labels.any? { |l| l.start_with?('for_end') }).to be true
    end
  end

  describe 'do-while loop' do
    it 'produces do-while blocks' do
      mod  = build_ir('void f(void){ int i=1; do { i=0; } while(i); }')
      func = function_named(mod, 'f')
      labels = func.blocks.map(&:label)
      expect(labels.any? { |l| l.start_with?('do_body') }).to be true
      expect(labels.any? { |l| l.start_with?('do_cond') }).to be true
      expect(labels.any? { |l| l.start_with?('do_end') }).to be true
    end
  end

  # ── Function calls ────────────────────────────────────────────────────────────

  describe 'function calls' do
    it 'emits a Call instruction' do
      mod  = build_ir('extern int g(int); void f(void){ g(1); }')
      func = function_named(mod, 'f')
      call = all_instrs(func).find { |i| i.is_a?(OCC::IR::Call) }
      expect(call).not_to be_nil
      expect(call.func).to be_a(OCC::IR::GlobalRef)
      expect(call.func.name).to eq('g')
    end

    it 'passes the correct number of arguments' do
      mod  = build_ir('extern int g(int,int); void f(void){ g(1,2); }')
      func = function_named(mod, 'f')
      call = all_instrs(func).find { |i| i.is_a?(OCC::IR::Call) }
      expect(call.args.length).to eq(2)
    end
  end

  # ── String literals ───────────────────────────────────────────────────────────

  describe 'string literals' do
    it 'adds strings to the module string table' do
      mod = build_ir('void f(void){ printf("hello"); }')
      expect(mod.strings).to include('hello')
    end

    it 'returns a StringRef for string literal expressions' do
      mod  = build_ir('void f(void){ printf("world"); }')
      func = function_named(mod, 'f')
      call = all_instrs(func).find { |i| i.is_a?(OCC::IR::Call) }
      expect(call.args.first).to be_a(OCC::IR::StringRef)
    end
  end

  # ── IR dump format ────────────────────────────────────────────────────────────

  describe 'dump' do
    it 'to_s produces readable IR for a simple function' do
      mod  = build_ir('int f(void){ return 1; }')
      dump = mod.to_s
      expect(dump).to include('f')
      expect(dump).to include('entry')
      expect(dump).to include('ret')
    end
  end
end
