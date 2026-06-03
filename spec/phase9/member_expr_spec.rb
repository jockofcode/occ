# frozen_string_literal: true

require 'open3'
require 'tmpdir'
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
require 'occ/codegen/base'
require 'occ/codegen/amd64'
require 'occ/codegen/arm64'
require 'occ/preprocessor'
require 'occ/driver'

RSpec.describe 'Phase 9: MemberExpr, type-sized loads/stores, stdlib headers' do
  def build_ir(src)
    tokens  = OCC::Lexer.new(src, '<test>').tokenize
    ast     = OCC::Parser.new(tokens).parse
    sa      = OCC::Semantic.new
    sa.analyze(ast)
    builder = OCC::IR::Builder.new
    builder.build(ast)
  end

  def all_instrs(func)
    func.blocks.flat_map(&:instrs)
  end

  def compile_and_run(src)
    Dir.mktmpdir do |dir|
      src_path = File.join(dir, 'test.c')
      exe_path = File.join(dir, 'test')
      File.write(src_path, src)
      options = OCC::Driver.parse_options([src_path, '-o', exe_path])
      OCC::Driver.compile_file(src_path, options)
      return { stdout: '', stderr: 'executable not produced', status: 1 } unless File.exist?(exe_path)
      stdout, stderr, status = Open3.capture3(exe_path)
      { stdout: stdout, stderr: stderr, status: status.exitstatus }
    end
  end

  shared_context 'native tools available' do
    before do
      skip 'clang not available' unless system('which clang > /dev/null 2>&1')
      skip 'as not available'    unless system('which as > /dev/null 2>&1')
    end
  end

  # ── MemberExpr: -> (pointer to struct) ──────────────────────────────────────

  describe 'MemberExpr -> (IR)' do
    it 'emits Load for p->field' do
      src = <<~C
        struct Point { int x; int y; };
        int f(struct Point *p) { return p->x; }
      C
      mod   = build_ir(src)
      func  = mod.functions.find { |fn| fn.name == 'f' }
      loads = all_instrs(func).select { |i| i.is_a?(OCC::IR::Load) }
      expect(loads).not_to be_empty
    end

    it 'emits Binary(:plus) for a non-zero field offset' do
      src = <<~C
        struct Point { int x; int y; };
        int f(struct Point *p) { return p->y; }
      C
      mod  = build_ir(src)
      func = mod.functions.find { |fn| fn.name == 'f' }
      bins = all_instrs(func).select { |i| i.is_a?(OCC::IR::Binary) && i.op == :plus }
      # y is at offset 4, so a Binary(:plus, ptr, 4) should be emitted
      expect(bins.any? { |b| b.right.is_a?(OCC::IR::Const) && b.right.value == 4 }).to be(true)
    end
  end

  describe 'MemberExpr -> (integration)', :slow do
    include_context 'native tools available'

    it 'reads first field of a heap-allocated struct' do
      src = <<~C
        extern int printf(const char *fmt, ...);
        extern void *malloc(unsigned long n);
        struct Point { int x; int y; };
        int main(void) {
          struct Point *p = (struct Point *)malloc(8);
          p->x = 10;
          p->y = 20;
          printf("%d\\n", p->x);
          return 0;
        }
      C
      result = compile_and_run(src)
      expect(result[:stdout].strip).to eq('10')
    end

    it 'reads second field (non-zero offset) of a heap-allocated struct' do
      src = <<~C
        extern int printf(const char *fmt, ...);
        extern void *malloc(unsigned long n);
        struct Point { int x; int y; };
        int main(void) {
          struct Point *p = (struct Point *)malloc(8);
          p->x = 10;
          p->y = 20;
          printf("%d\\n", p->y);
          return 0;
        }
      C
      result = compile_and_run(src)
      expect(result[:stdout].strip).to eq('20')
    end

    it 'reads fields via pointer from a function parameter' do
      src = <<~C
        extern int printf(const char *fmt, ...);
        extern void *malloc(unsigned long n);
        struct Pair { int a; int b; };
        int sum(struct Pair *p) { return p->a + p->b; }
        int main(void) {
          struct Pair *pair = (struct Pair *)malloc(8);
          pair->a = 3;
          pair->b = 4;
          printf("%d\\n", sum(pair));
          return 0;
        }
      C
      result = compile_and_run(src)
      expect(result[:stdout].strip).to eq('7')
    end
  end

  # ── Type-sized GEP: correct array element stride ─────────────────────────────

  describe 'GEP element stride (IR)' do
    it 'uses elem_size=4 for int array indexing' do
      src = <<~C
        int f(int *arr) { return arr[2]; }
      C
      mod   = build_ir(src)
      func  = mod.functions.find { |fn| fn.name == 'f' }
      geps  = all_instrs(func).select { |i| i.is_a?(OCC::IR::Gep) }
      expect(geps.first&.elem_size).to eq(4)
    end

    it 'uses elem_size=1 for char pointer indexing' do
      src = <<~C
        char f(char *s) { return s[3]; }
      C
      mod   = build_ir(src)
      func  = mod.functions.find { |fn| fn.name == 'f' }
      geps  = all_instrs(func).select { |i| i.is_a?(OCC::IR::Gep) }
      expect(geps.first&.elem_size).to eq(1)
    end
  end

  describe 'type-sized array access (integration)', :slow do
    include_context 'native tools available'

    it 'reads correct bytes from a char string' do
      src = <<~C
        extern int printf(const char *fmt, ...);
        int main(void) {
          char msg[5];
          msg[0] = 72;
          msg[1] = 101;
          msg[2] = 108;
          msg[3] = 108;
          msg[4] = 111;
          printf("%c%c%c%c%c\\n", msg[0], msg[1], msg[2], msg[3], msg[4]);
          return 0;
        }
      C
      result = compile_and_run(src)
      expect(result[:stdout].strip).to eq('Hello')
    end

    it 'reads correct ints from an int array' do
      src = <<~C
        extern int printf(const char *fmt, ...);
        extern void *malloc(unsigned long n);
        int main(void) {
          int *arr = (int *)malloc(12);
          arr[0] = 100;
          arr[1] = 200;
          arr[2] = 300;
          printf("%d %d %d\\n", arr[0], arr[1], arr[2]);
          return 0;
        }
      C
      result = compile_and_run(src)
      expect(result[:stdout].strip).to eq('100 200 300')
    end
  end

  # ── Standard library headers ─────────────────────────────────────────────────

  describe 'standard library headers' do
    it 'preprocesses #include <stddef.h> without error' do
      src = <<~C
        #include <stddef.h>
        size_t f(void) { return sizeof(int); }
      C
      expect { OCC::Driver.compile_source(src, '<test>', {}) }.not_to raise_error
    end

    it 'preprocesses #include <stdint.h> without error' do
      src = <<~C
        #include <stdint.h>
        uint32_t f(void) { return 42; }
      C
      expect { OCC::Driver.compile_source(src, '<test>', {}) }.not_to raise_error
    end

    it 'preprocesses #include <stdbool.h> without error' do
      src = <<~C
        #include <stdbool.h>
        bool f(void) { return true; }
      C
      expect { OCC::Driver.compile_source(src, '<test>', {}) }.not_to raise_error
    end

    it 'preprocesses #include <limits.h> without error' do
      src = <<~C
        #include <limits.h>
        int f(void) { return INT_MAX; }
      C
      expect { OCC::Driver.compile_source(src, '<test>', {}) }.not_to raise_error
    end

    it 'preprocesses #include <float.h> without error' do
      src = <<~C
        #include <float.h>
        int f(void) { return FLT_DIG; }
      C
      expect { OCC::Driver.compile_source(src, '<test>', {}) }.not_to raise_error
    end

    it 'preprocesses #include <stdarg.h> without error' do
      src = <<~C
        #include <stdarg.h>
        int f(int n, ...) { return n; }
      C
      expect { OCC::Driver.compile_source(src, '<test>', {}) }.not_to raise_error
    end

    it 'NULL expands to ((void*)0) from stddef.h' do
      src = <<~C
        #include <stddef.h>
        void *f(void) { return NULL; }
      C
      asm = OCC::Driver.compile_source(src, '<test>', {})
      expect(asm).to match(/globl.*f/)
    end

    it 'INT_MAX from limits.h compiles without error' do
      src = <<~C
        #include <limits.h>
        int f(void) { return INT_MAX; }
      C
      asm = OCC::Driver.compile_source(src, '<test>', {})
      expect(asm).to match(/globl.*f/)
    end
  end

  describe 'standard library headers (integration)', :slow do
    include_context 'native tools available'

    it 'uint32_t variable works at runtime' do
      src = <<~C
        #include <stdint.h>
        extern int printf(const char *fmt, ...);
        int main(void) {
          uint32_t x = 42;
          printf("%d\\n", (int)x);
          return 0;
        }
      C
      result = compile_and_run(src)
      expect(result[:stdout].strip).to eq('42')
    end

    it 'INT_MAX constant is usable at runtime' do
      src = <<~C
        #include <limits.h>
        extern int printf(const char *fmt, ...);
        int main(void) {
          printf("%d\\n", INT_MAX);
          return 0;
        }
      C
      result = compile_and_run(src)
      expect(result[:stdout].strip).to eq('2147483647')
    end

    it 'bool from stdbool.h works at runtime' do
      src = <<~C
        #include <stdbool.h>
        extern int printf(const char *fmt, ...);
        int main(void) {
          bool flag = true;
          printf("%d\\n", flag);
          return 0;
        }
      C
      result = compile_and_run(src)
      expect(result[:stdout].strip).to eq('1')
    end
  end
end
