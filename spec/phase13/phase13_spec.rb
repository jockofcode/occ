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

RSpec.describe 'Phase 13: GCC Extension Compatibility' do
  def compile_and_run(src, defines: [])
    Dir.mktmpdir do |dir|
      src_path = File.join(dir, 'test.c')
      exe_path = File.join(dir, 'test')
      File.write(src_path, src)
      flags = [src_path, '-o', exe_path] + defines.flat_map { |d| ['-D', d] }
      options = OCC::Driver.parse_options(flags)
      OCC::Driver.compile_file(src_path, options)
      return { stdout: '', stderr: 'executable not produced', status: 1 } unless File.exist?(exe_path)
      stdout, stderr, status = Open3.capture3(exe_path)
      { stdout: stdout, stderr: stderr, status: status.exitstatus }
    end
  end

  def preprocess_text(src)
    pp = OCC::Preprocessor.new(src, '<test>')
    pp.process
  end

  def parse(src)
    expanded = preprocess_text(src)
    tokens = OCC::Lexer.new(expanded, '<test>').tokenize
    OCC::Parser.new(tokens).parse
  end

  def build_ir(src)
    expanded = preprocess_text(src)
    tokens   = OCC::Lexer.new(expanded, '<test>').tokenize
    ast      = OCC::Parser.new(tokens).parse
    sa       = OCC::Semantic.new
    sa.analyze(ast)
    OCC::IR::Builder.new.build(ast)
  end

  shared_context 'native tools available' do
    before do
      skip 'clang not available' unless system('which clang > /dev/null 2>&1')
      skip 'as not available'    unless system('which as > /dev/null 2>&1')
    end
  end

  # ── Statement expressions ─────────────────────────────────────────────────

  describe 'statement expressions ({ ... })' do
    it 'parses ({ expr; }) as a StmtExpr AST node' do
      # ARRANGE
      src = 'int f(void) { return ({ 42; }); }'
      # ACT
      ast = parse(src)
      # ASSERT
      fn = ast.decls.first
      ret = fn.body.items.first
      expect(ret.value).to be_a(OCC::AST::StmtExpr)
    end

    describe 'integration', :integration do
      include_context 'native tools available'

      it 'emits the last expression value as the result' do
        # ARRANGE
        src = <<~C
          #include <stdio.h>
          int main(void) {
            int x = ({ int a = 3; int b = 4; a + b; });
            printf("%d\\n", x);
            return 0;
          }
        C
        # ACT
        result = compile_and_run(src)
        # ASSERT
        expect(result[:status]).to eq(0)
        expect(result[:stdout].strip).to eq('7')
      end

      it 'works in a macro expansion using __typeof__' do
        # ARRANGE
        src = <<~C
          #include <stdio.h>
          #define MAX(a, b) ({ __typeof__(a) _a = (a); __typeof__(b) _b = (b); _a > _b ? _a : _b; })
          int main(void) {
            int x = MAX(3, 7);
            printf("%d\\n", x);
            return 0;
          }
        C
        # ACT
        result = compile_and_run(src)
        # ASSERT
        expect(result[:status]).to eq(0)
        expect(result[:stdout].strip).to eq('7')
      end

      it 'evaluates side effects in the body' do
        # ARRANGE
        src = <<~C
          #include <stdio.h>
          int g = 0;
          int main(void) {
            ({ g = 5; });
            printf("%d\\n", g);
            return 0;
          }
        C
        # ACT
        result = compile_and_run(src)
        # ASSERT
        expect(result[:status]).to eq(0)
        expect(result[:stdout].strip).to eq('5')
      end
    end
  end

  # ── __typeof__ ────────────────────────────────────────────────────────────

  describe '__typeof__ type reflection' do
    it 'parses __typeof__(expr) without error' do
      # ARRANGE
      src = 'int x; __typeof__(x) y;'
      # ACT / ASSERT
      expect { parse(src) }.not_to raise_error
    end

    it 'parses __typeof__(type-name) without error' do
      # ARRANGE
      src = '__typeof__(int) x; __typeof__(unsigned long) y;'
      # ACT / ASSERT
      expect { parse(src) }.not_to raise_error
    end

    describe 'integration', :integration do
      include_context 'native tools available'

      it 'preserves double type in a SWAP macro' do
        # ARRANGE
        src = <<~C
          #include <stdio.h>
          #define SWAP(a,b) do { __typeof__(a) _t = (a); (a) = (b); (b) = _t; } while(0)
          int main(void) {
            double x = 1.5, y = 2.5;
            SWAP(x, y);
            printf("%.1f %.1f\\n", x, y);
            return 0;
          }
        C
        # ACT
        result = compile_and_run(src)
        # ASSERT
        expect(result[:status]).to eq(0)
        expect(result[:stdout].strip).to eq('2.5 1.5')
      end

      it 'works with pointer arithmetic' do
        # ARRANGE
        src = <<~C
          #include <stdio.h>
          int main(void) {
            int arr[3] = {10, 20, 30};
            __typeof__(arr[0]) *p = &arr[1];
            printf("%d\\n", *p);
            return 0;
          }
        C
        # ACT
        result = compile_and_run(src)
        # ASSERT
        expect(result[:status]).to eq(0)
        expect(result[:stdout].strip).to eq('20')
      end
    end
  end

  # ── __builtin_offsetof ────────────────────────────────────────────────────

  describe '__builtin_offsetof' do
    it 'parses __builtin_offsetof as a BuiltinOffsetof AST node' do
      # ARRANGE
      src = <<~C
        struct Foo { int a; long b; };
        int x = __builtin_offsetof(struct Foo, b);
      C
      # ACT
      ast = parse(src)
      # ASSERT
      decl = ast.decls.last
      init = decl.declarators.first[:init]
      expect(init).to be_a(OCC::AST::BuiltinOffsetof)
      expect(init.member_chain).to eq(['b'])
    end

    describe 'integration', :integration do
      include_context 'native tools available'

      it 'computes the correct byte offset' do
        # ARRANGE
        src = <<~C
          #include <stdio.h>
          struct Point { int x; int y; double z; };
          int main(void) {
            printf("%zu\\n", __builtin_offsetof(struct Point, z));
            return 0;
          }
        C
        # ACT
        result = compile_and_run(src)
        # ASSERT
        expect(result[:status]).to eq(0)
        expect(result[:stdout].strip).to eq('8')
      end

      it 'computes nested field offset' do
        # ARRANGE
        src = <<~C
          #include <stdio.h>
          struct Inner { int x; int y; };
          struct Outer { long a; struct Inner b; };
          int main(void) {
            printf("%zu %zu\\n",
              __builtin_offsetof(struct Outer, b),
              __builtin_offsetof(struct Outer, b.y));
            return 0;
          }
        C
        # ACT
        result = compile_and_run(src)
        # ASSERT
        expect(result[:status]).to eq(0)
        expect(result[:stdout].strip).to eq('8 12')
      end
    end
  end

  # ── __builtin_clz / __builtin_ctz / __builtin_popcount ───────────────────

  describe '__builtin_clz / __builtin_ctz / __builtin_popcount', :integration do
    include_context 'native tools available'

    it 'computes leading zeros' do
      # ARRANGE
      src = <<~C
        #include <stdio.h>
        int main(void) {
          printf("%d\\n", __builtin_clz(1));
          printf("%d\\n", __builtin_clz(0x80000000u));
          return 0;
        }
      C
      # ACT
      result = compile_and_run(src)
      # ASSERT
      expect(result[:status]).to eq(0)
      lines = result[:stdout].split
      expect(lines[0].to_i).to eq(31)
      expect(lines[1].to_i).to eq(0)
    end

    it 'computes trailing zeros' do
      # ARRANGE
      src = <<~C
        #include <stdio.h>
        int main(void) {
          printf("%d\\n", __builtin_ctz(8));
          printf("%d\\n", __builtin_ctz(1));
          return 0;
        }
      C
      # ACT
      result = compile_and_run(src)
      # ASSERT
      expect(result[:status]).to eq(0)
      lines = result[:stdout].split
      expect(lines[0].to_i).to eq(3)
      expect(lines[1].to_i).to eq(0)
    end

    it 'counts set bits with popcount' do
      # ARRANGE
      src = <<~C
        #include <stdio.h>
        int main(void) {
          printf("%d\\n", __builtin_popcount(0xFF));
          printf("%d\\n", __builtin_popcount(0));
          printf("%d\\n", __builtin_popcount(7));
          return 0;
        }
      C
      # ACT
      result = compile_and_run(src)
      # ASSERT
      expect(result[:status]).to eq(0)
      lines = result[:stdout].split
      expect(lines[0].to_i).to eq(8)
      expect(lines[1].to_i).to eq(0)
      expect(lines[2].to_i).to eq(3)
    end

    it 'byte-swaps with bswap32' do
      # ARRANGE
      src = <<~C
        #include <stdio.h>
        #include <stdint.h>
        int main(void) {
          uint32_t v = __builtin_bswap32(0x01020304);
          printf("0x%08X\\n", v);
          return 0;
        }
      C
      # ACT
      result = compile_and_run(src)
      # ASSERT
      expect(result[:status]).to eq(0)
      expect(result[:stdout].strip).to eq('0x04030201')
    end
  end

  # ── asm statement ─────────────────────────────────────────────────────────

  describe 'asm statement' do
    it 'parses bare asm("...") as a no-op statement' do
      # ARRANGE
      src = <<~C
        void f(void) {
          asm("nop");
        }
      C
      # ACT / ASSERT
      expect { parse(src) }.not_to raise_error
    end

    describe 'integration', :integration do
      include_context 'native tools available'

      it 'parses asm volatile("" ::: "memory") and program continues normally' do
        # ARRANGE
        src = <<~C
          #include <stdio.h>
          int main(void) {
            int x = 42;
            asm volatile("" ::: "memory");
            printf("%d\\n", x);
            return 0;
          }
        C
        # ACT
        result = compile_and_run(src)
        # ASSERT
        expect(result[:status]).to eq(0)
        expect(result[:stdout].strip).to eq('42')
      end
    end
  end

  # ── __int128 ─────────────────────────────────────────────────────────────

  describe '__int128 type' do
    it 'parses __int128 as a type specifier without error' do
      # ARRANGE
      src = '__int128 x = 0; unsigned __int128 y = 0;'
      # ACT / ASSERT
      expect { parse(src) }.not_to raise_error
    end

    it 'allows __int128 in a typedef and IR build' do
      # ARRANGE
      src = 'typedef __int128 int128_t; int128_t x = 0;'
      # ACT / ASSERT
      expect { build_ir(src) }.not_to raise_error
    end
  end

  # ── Alternate keyword spellings ───────────────────────────────────────────

  describe 'alternate keyword spellings' do
    it 'treats __inline__ as inline via preprocessor' do
      # ARRANGE / ACT / ASSERT
      expanded = preprocess_text('__inline__ int f(void) { return 0; }')
      expect(expanded).to include('inline')
      expect(expanded).not_to include('__inline__')
    end

    it 'treats __volatile__ as volatile via preprocessor' do
      # ARRANGE / ACT / ASSERT
      expanded = preprocess_text('__volatile__ int x;')
      expect(expanded).to include('volatile')
      expect(expanded).not_to include('__volatile__')
    end

    it 'treats __const__ as const via preprocessor' do
      # ARRANGE / ACT / ASSERT
      expanded = preprocess_text('__const__ int x = 1;')
      expect(expanded).to include('const')
      expect(expanded).not_to include('__const__')
    end

    it 'treats __signed__ as signed via preprocessor' do
      # ARRANGE / ACT / ASSERT
      expanded = preprocess_text('__signed__ char c;')
      expect(expanded).to include('signed')
      expect(expanded).not_to include('__signed__')
    end
  end

  # ── __extension__ ────────────────────────────────────────────────────────

  describe '__extension__' do
    it 'is silently discarded by the preprocessor' do
      # ARRANGE / ACT / ASSERT
      expanded = preprocess_text('__extension__ typedef unsigned long long u64;')
      expect(expanded).not_to include('__extension__')
      expect(expanded).to include('typedef')
    end
  end

  # ── __builtin_alloca ─────────────────────────────────────────────────────

  describe '__builtin_alloca' do
    describe 'integration', :integration do
      include_context 'native tools available'

      it 'restores the fixed stack frame before returning after dynamic allocation' do
        # ARRANGE
        src = <<~C
          #include <stdio.h>
          int leaf(void) { return 7; }
          int f(int n) {
            char *p = (char *)__builtin_alloca(n);
            p[0] = 35;
            return leaf() + p[0];
          }
          int main(void) {
            printf("%d\\n", f(32));
            return 0;
          }
        C
        # ACT
        result = compile_and_run(src)
        # ASSERT
        expect(result[:stdout].strip).to eq('42')
      end
    end
  end

  # ── _Thread_local / TLS ──────────────────────────────────────────────────

  describe '_Thread_local storage' do
    it 'parses _Thread_local variable declaration without error' do
      # ARRANGE
      src = '_Thread_local int errno_val;'
      # ACT / ASSERT
      expect { parse(src) }.not_to raise_error
    end

    it 'parses __thread variable declaration without error' do
      # ARRANGE
      src = '__thread int counter;'
      # ACT / ASSERT
      expect { parse(src) }.not_to raise_error
    end

    it 'registers a _Thread_local global in tls_globals in the IR module' do
      # ARRANGE
      src = '_Thread_local int tls_var;'
      # ACT
      mod = build_ir(src)
      # ASSERT
      expect(mod.tls_globals).to have_key('tls_var')
    end

    it 'does not register a _Thread_local global in the regular globals map' do
      # ARRANGE
      src = '_Thread_local int tls_only;'
      # ACT
      mod = build_ir(src)
      # ASSERT
      expect(mod.globals).not_to have_key('tls_only')
    end

    it 'compiles a _Thread_local int and reads/writes it correctly' do
      # ARRANGE
      src = <<~C
        #include <stdio.h>
        _Thread_local int tls_counter = 0;
        int main(void) {
          tls_counter = 42;
          printf("%d\\n", tls_counter);
          return 0;
        }
      C
      # ACT
      result = compile_and_run(src)
      # ASSERT
      expect(result[:stdout].strip).to eq('42')
    end

    it 'compiles a _Thread_local long and accumulates correctly' do
      # ARRANGE
      src = <<~C
        #include <stdio.h>
        _Thread_local long tls_sum = 0;
        int main(void) {
          tls_sum += 10;
          tls_sum += 20;
          tls_sum += 12;
          printf("%ld\\n", tls_sum);
          return 0;
        }
      C
      # ACT
      result = compile_and_run(src)
      # ASSERT
      expect(result[:stdout].strip).to eq('42')
    end
  end
end
