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

RSpec.describe 'Phase 9: Language Coverage' do
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

  # ── goto ─────────────────────────────────────────────────────────────────────

  describe 'goto statement (IR)' do
    it 'emits a Jump instruction targeting the label' do
      src = <<~C
        int f(void) {
          goto done;
          done: return 1;
        }
      C
      mod  = build_ir(src)
      func = mod.functions.find { |f| f.name == 'f' }
      jumps = all_instrs(func).select { |i| i.is_a?(OCC::IR::Jump) }
      expect(jumps.map(&:target)).to include('done')
    end

    it 'creates a block for the label target' do
      src = <<~C
        int f(void) {
          goto done;
          done: return 2;
        }
      C
      mod    = build_ir(src)
      func   = mod.functions.find { |f| f.name == 'f' }
      labels = func.blocks.map(&:label)
      expect(labels).to include('done')
    end
  end

  describe 'goto (integration)', :slow do
    include_context 'native tools available'

    it 'jumps over unreachable code and returns correct value' do
      src = <<~C
        int main(void) {
          goto skip;
          return 99;
          skip: return 0;
        }
      C
      result = compile_and_run(src)
      expect(result[:status]).to eq(0)
    end
  end

  # ── switch/case ───────────────────────────────────────────────────────────────

  describe 'switch/case dispatch (IR)' do
    it 'emits Binary equality comparisons for each case value' do
      src = <<~C
        int f(int x) {
          switch (x) {
            case 1: return 10;
            case 2: return 20;
            default: return 0;
          }
        }
      C
      mod    = build_ir(src)
      func   = mod.functions.find { |f| f.name == 'f' }
      bins   = all_instrs(func).select { |i| i.is_a?(OCC::IR::Binary) && i.op == :eq }
      expect(bins.length).to be >= 2
    end

    it 'emits CondJump instructions for case dispatch' do
      src = <<~C
        int f(int x) {
          switch (x) {
            case 5: return 1;
            default: return 0;
          }
        }
      C
      mod  = build_ir(src)
      func = mod.functions.find { |f| f.name == 'f' }
      cjs  = all_instrs(func).select { |i| i.is_a?(OCC::IR::CondJump) }
      expect(cjs).not_to be_empty
    end

    it 'creates blocks for each case and default' do
      src = <<~C
        int f(int x) {
          switch (x) {
            case 3: return 33;
            case 7: return 77;
            default: return 0;
          }
        }
      C
      mod    = build_ir(src)
      func   = mod.functions.find { |f| f.name == 'f' }
      labels = func.blocks.map(&:label)
      expect(labels.any? { |l| l.include?('switch_case') }).to be(true)
      expect(labels.any? { |l| l.include?('switch_default') }).to be(true)
      expect(labels.any? { |l| l.include?('switch_end') }).to be(true)
    end
  end

  describe 'switch/case (integration)', :slow do
    include_context 'native tools available'

    it 'dispatches to the matching case' do
      src = <<~C
        extern int printf(const char *fmt, ...);
        int main(void) {
          int x = 2;
          switch (x) {
            case 1: printf("one\\n");   break;
            case 2: printf("two\\n");   break;
            case 3: printf("three\\n"); break;
            default: printf("other\\n"); break;
          }
          return 0;
        }
      C
      result = compile_and_run(src)
      expect(result[:stdout].strip).to eq('two')
    end

    it 'hits the default case when no case matches' do
      src = <<~C
        extern int printf(const char *fmt, ...);
        int main(void) {
          int x = 99;
          switch (x) {
            case 1: printf("one\\n"); break;
            case 2: printf("two\\n"); break;
            default: printf("default\\n"); break;
          }
          return 0;
        }
      C
      result = compile_and_run(src)
      expect(result[:stdout].strip).to eq('default')
    end

    it 'supports fall-through between cases' do
      src = <<~C
        extern int printf(const char *fmt, ...);
        int main(void) {
          int x = 1;
          int result = 0;
          switch (x) {
            case 1: result = result + 1;
            case 2: result = result + 2;
            default: result = result + 4;
          }
          printf("%d\\n", result);
          return 0;
        }
      C
      result = compile_and_run(src)
      expect(result[:stdout].strip).to eq('7')
    end
  end

  # ── sizeof ────────────────────────────────────────────────────────────────────

  describe 'sizeof(type) (IR)' do
    it 'returns 1 for sizeof(char)' do
      src = 'int f(void){ return sizeof(char); }'
      mod  = build_ir(src)
      func = mod.functions.find { |f| f.name == 'f' }
      ret  = all_instrs(func).find { |i| i.is_a?(OCC::IR::Return) }
      expect(ret.value).to be_a(OCC::IR::Const)
      expect(ret.value.value).to eq(1)
    end

    it 'returns 4 for sizeof(int)' do
      src = 'int f(void){ return sizeof(int); }'
      mod  = build_ir(src)
      func = mod.functions.find { |f| f.name == 'f' }
      ret  = all_instrs(func).find { |i| i.is_a?(OCC::IR::Return) }
      expect(ret.value).to be_a(OCC::IR::Const)
      expect(ret.value.value).to eq(4)
    end

    it 'returns 8 for sizeof(long)' do
      src = 'int f(void){ return sizeof(long); }'
      mod  = build_ir(src)
      func = mod.functions.find { |f| f.name == 'f' }
      ret  = all_instrs(func).find { |i| i.is_a?(OCC::IR::Return) }
      expect(ret.value).to be_a(OCC::IR::Const)
      expect(ret.value.value).to eq(8)
    end

    it 'returns 2 for sizeof(short)' do
      src = 'int f(void){ return sizeof(short); }'
      mod  = build_ir(src)
      func = mod.functions.find { |f| f.name == 'f' }
      ret  = all_instrs(func).find { |i| i.is_a?(OCC::IR::Return) }
      expect(ret.value).to be_a(OCC::IR::Const)
      expect(ret.value.value).to eq(2)
    end
  end

  describe 'sizeof (integration)', :slow do
    include_context 'native tools available'

    it 'sizeof(char) == 1 at runtime' do
      src = <<~C
        extern int printf(const char *fmt, ...);
        int main(void) {
          printf("%d\\n", (int)sizeof(char));
          return 0;
        }
      C
      result = compile_and_run(src)
      expect(result[:stdout].strip).to eq('1')
    end

    it 'sizeof(int) == 4 at runtime' do
      src = <<~C
        extern int printf(const char *fmt, ...);
        int main(void) {
          printf("%d\\n", (int)sizeof(int));
          return 0;
        }
      C
      result = compile_and_run(src)
      expect(result[:stdout].strip).to eq('4')
    end

    it 'sizeof(long) == 8 at runtime' do
      src = <<~C
        extern int printf(const char *fmt, ...);
        int main(void) {
          printf("%d\\n", (int)sizeof(long));
          return 0;
        }
      C
      result = compile_and_run(src)
      expect(result[:stdout].strip).to eq('8')
    end
  end

  # ── global variable initialization ───────────────────────────────────────────

  describe 'global variable initialization (IR)' do
    it 'stores the init value in the module globals table' do
      src = 'int g = 42;'
      mod = build_ir(src)
      expect(mod.globals['g']).not_to be_nil
      expect(mod.globals['g'][:init]).to eq(42)
    end

    it 'stores nil init for uninitialized globals' do
      src = 'int g;'
      mod = build_ir(src)
      expect(mod.globals['g'][:init]).to be_nil
    end
  end

  describe 'global variable initialization (assembly)' do
    it 'emits a .data section for an initialized global' do
      src = 'int counter = 7;'
      asm = OCC::Driver.compile_source(src, '<test>', {})
      expect(asm).to include('.quad 7').or include('.long 7')
    end

    it 'does not emit .data for uninitialized global' do
      src = 'int counter;'
      asm = OCC::Driver.compile_source(src, '<test>', {})
      expect(asm).to include('.comm')
    end
  end

  describe 'global variable initialization (integration)', :slow do
    include_context 'native tools available'

    it 'global initializes to the declared value' do
      src = <<~C
        extern int printf(const char *fmt, ...);
        int answer = 42;
        int main(void) {
          printf("%d\\n", answer);
          return 0;
        }
      C
      result = compile_and_run(src)
      expect(result[:stdout].strip).to eq('42')
    end

    it 'global can be assigned and read back' do
      src = <<~C
        extern int printf(const char *fmt, ...);
        int counter = 0;
        int main(void) {
          counter = 5;
          printf("%d\\n", counter);
          return 0;
        }
      C
      result = compile_and_run(src)
      expect(result[:stdout].strip).to eq('5')
    end
  end

  # ── cast ──────────────────────────────────────────────────────────────────────

  describe 'cast expression (IR)' do
    it 'emits a Cast instruction' do
      src = 'int f(long x){ return (int)x; }'
      mod   = build_ir(src)
      func  = mod.functions.find { |f| f.name == 'f' }
      casts = all_instrs(func).select { |i| i.is_a?(OCC::IR::Cast) }
      expect(casts).not_to be_empty
    end

    it 'stores the target type name on the Cast instruction' do
      src = 'int f(long x){ return (int)x; }'
      mod   = build_ir(src)
      func  = mod.functions.find { |f| f.name == 'f' }
      cast  = all_instrs(func).find { |i| i.is_a?(OCC::IR::Cast) }
      expect(cast.to_type).to include('int')
    end
  end

  # ── cast truncation (integration) ────────────────────────────────────────────

  describe 'int→int cast truncation (integration)', :slow do
    include_context 'native tools available'

    it 'truncates to char' do
      src = <<~C
        extern int printf(const char *fmt, ...);
        int main(void) {
          int x = 0x1FF;
          char c = (char)x;
          printf("%d\\n", (int)c);
          return 0;
        }
      C
      result = compile_and_run(src)
      expect(result[:stdout].strip).to eq('-1')
    end

    it 'truncates to unsigned char' do
      src = <<~C
        extern int printf(const char *fmt, ...);
        int main(void) {
          int x = 0x1FF;
          unsigned char c = (unsigned char)x;
          printf("%d\\n", (int)c);
          return 0;
        }
      C
      result = compile_and_run(src)
      expect(result[:stdout].strip).to eq('255')
    end

    it 'truncates to short' do
      src = <<~C
        extern int printf(const char *fmt, ...);
        int main(void) {
          long x = 0x18000L;
          short s = (short)x;
          printf("%d\\n", (int)s);
          return 0;
        }
      C
      result = compile_and_run(src)
      expect(result[:stdout].strip).to eq('-32768')
    end
  end

  # ── float globals (integration) ───────────────────────────────────────────────

  describe 'float/double global initialization (integration)', :slow do
    include_context 'native tools available'

    it 'initializes a double global and reads it back' do
      src = <<~C
        extern int printf(const char *fmt, ...);
        double pi = 3.14;
        int main(void) {
          printf("%.2f\\n", pi);
          return 0;
        }
      C
      result = compile_and_run(src)
      expect(result[:stdout].strip).to eq('3.14')
    end
  end

  # ── string pointer global (integration) ──────────────────────────────────────

  describe 'string pointer global initialization (integration)', :slow do
    include_context 'native tools available'

    it 'initializes a char* global with a string literal' do
      src = <<~C
        extern int printf(const char *fmt, ...);
        const char *greeting = "hello";
        int main(void) {
          printf("%s\\n", greeting);
          return 0;
        }
      C
      result = compile_and_run(src)
      expect(result[:stdout].strip).to eq('hello')
    end
  end

  # ── _Static_assert ────────────────────────────────────────────────────────────

  describe '_Static_assert' do
    it 'passes when condition is non-zero' do
      src = <<~C
        _Static_assert(1, "always true");
        int f(void) { return 0; }
      C
      expect { build_ir(src) }.not_to raise_error
    end

    it 'raises SemanticError when condition is zero' do
      src = <<~C
        _Static_assert(0, "always false");
        int f(void) { return 0; }
      C
      expect { build_ir(src) }.to raise_error(OCC::SemanticError, /always false/)
    end

    it 'passes for a true sizeof comparison' do
      src = <<~C
        _Static_assert(sizeof(int) == 4, "int must be 4 bytes");
        int f(void) { return 0; }
      C
      expect { build_ir(src) }.not_to raise_error
    end
  end

  # ── _Generic ──────────────────────────────────────────────────────────────────

  # ── sizeof string literal ─────────────────────────────────────────────────────

  describe 'sizeof(string_literal) and char arr[] = "..."' do
    include_context 'native tools available'

    it 'returns the correct length for sizeof string literals' do
      src = <<~C
        #include <stddef.h>
        extern int printf(const char *fmt, ...);
        int main(void) {
          printf("%zu %zu %zu %zu\\n",
            sizeof("true"), sizeof("false"), sizeof("null"), sizeof(""));
          return 0;
        }
      C
      result = compile_and_run(src)
      expect(result[:stdout].strip).to eq('5 6 5 1')
    end

    it 'infers array size from string literal initializer' do
      src = <<~C
        #include <stddef.h>
        extern int printf(const char *fmt, ...);
        int main(void) {
          char arr[] = "hello";
          printf("%zu\\n", sizeof(arr));
          return 0;
        }
      C
      result = compile_and_run(src)
      expect(result[:stdout].strip).to eq('6')
    end

    it 'SIZEOF_TOKEN macro computes correct token sizes' do
      src = <<~C
        #include <stddef.h>
        extern int printf(const char *fmt, ...);
        int main(void) {
          size_t n = sizeof("true") - 1;
          printf("%zu\\n", n);
          return 0;
        }
      C
      result = compile_and_run(src)
      expect(result[:stdout].strip).to eq('4')
    end
  end

  # ── char literal sign extension ───────────────────────────────────────────────

  describe 'char literal sign extension (values > 127)' do
    include_context 'native tools available'

    it 'sign-extends hex char literals > 127 to match clang behavior' do
      # Write C source via file to avoid Ruby UTF-8 encoding issues with raw high bytes
      result = Dir.mktmpdir do |dir|
        src_path = File.join(dir, 'test.c')
        # Use File.binwrite so raw bytes in C source aren't re-encoded
        File.binwrite(src_path, <<~'C')
          extern int printf(const char *fmt, ...);
          int main(void) {
            int v = '\xEF';
            printf("%d\n", v);
            return 0;
          }
        C
        exe = File.join(dir, 'test')
        opts = OCC::Driver.parse_options([src_path, '-o', exe])
        OCC::Driver.compile_file(src_path, opts)
        next { stdout: '', stderr: 'no exe', status: 1 } unless File.exist?(exe)
        require 'open3'
        out, _e, st = Open3.capture3(exe)
        { stdout: out, status: st.exitstatus }
      end
      expect(result[:stdout].strip).to eq('-17')
    end

    it 'correctly compares high-byte char literals for BOM detection' do
      result = Dir.mktmpdir do |dir|
        src_path = File.join(dir, 'test.c')
        File.binwrite(src_path, <<~'C')
          extern int printf(const char *fmt, ...);
          int main(void) {
            const char buf[] = {'\xEF', '\xBB', '\xBF', '{', '}', '\0'};
            const char *s = buf;
            if (s[0] == '\xEF' && s[1] == '\xBB' && s[2] == '\xBF') {
              printf("BOM\n");
            } else {
              printf("NO\n");
            }
            return 0;
          }
        C
        exe = File.join(dir, 'test')
        opts = OCC::Driver.parse_options([src_path, '-o', exe])
        OCC::Driver.compile_file(src_path, opts)
        next { stdout: '', stderr: 'no exe', status: 1 } unless File.exist?(exe)
        require 'open3'
        out, _e, st = Open3.capture3(exe)
        { stdout: out, status: st.exitstatus }
      end
      expect(result[:stdout].strip).to eq('BOM')
    end
  end

  # ── hex escape sequences are raw bytes ───────────────────────────────────────

  describe 'hex escape sequences in string literals' do
    include_context 'native tools available'

    it 'stores \\xNN as a single raw byte, not UTF-8 encoded codepoint' do
      result = Dir.mktmpdir do |dir|
        src_path = File.join(dir, 'test.c')
        File.binwrite(src_path, <<~'C')
          #include <string.h>
          extern int printf(const char *fmt, ...);
          int main(void) {
            const char *s = "\x80";
            printf("%zu %d\n", strlen(s), (unsigned char)s[0]);
            return 0;
          }
        C
        exe = File.join(dir, 'test')
        opts = OCC::Driver.parse_options([src_path, '-o', exe])
        OCC::Driver.compile_file(src_path, opts)
        next { stdout: '', stderr: 'no exe', status: 1 } unless File.exist?(exe)
        require 'open3'
        out, _e, st = Open3.capture3(exe)
        { stdout: out, status: st.exitstatus }
      end
      expect(result[:stdout].strip).to eq('1 128')
    end

    it 'stores multi-byte hex sequences as individual raw bytes' do
      result = Dir.mktmpdir do |dir|
        src_path = File.join(dir, 'test.c')
        File.binwrite(src_path, <<~'C')
          #include <string.h>
          extern int printf(const char *fmt, ...);
          int main(void) {
            const char *s = "\xef\xbb\xbf";
            printf("%zu %d %d %d\n", strlen(s),
              (unsigned char)s[0], (unsigned char)s[1], (unsigned char)s[2]);
            return 0;
          }
        C
        exe = File.join(dir, 'test')
        opts = OCC::Driver.parse_options([src_path, '-o', exe])
        OCC::Driver.compile_file(src_path, opts)
        next { stdout: '', stderr: 'no exe', status: 1 } unless File.exist?(exe)
        require 'open3'
        out, _e, st = Open3.capture3(exe)
        { stdout: out, status: st.exitstatus }
      end
      expect(result[:stdout].strip).to eq('3 239 187 191')
    end
  end

  # ── int-to-float implicit conversion at call sites ────────────────────────────

  describe 'implicit int-to-float conversion at function call sites' do
    include_context 'native tools available'

    it 'converts int argument to double when function expects double' do
      src = <<~C
        extern int printf(const char *fmt, ...);
        void show(double d) { printf("%.1f\\n", d); }
        int main(void) {
          show(25);
          show(-1);
          show(0);
          return 0;
        }
      C
      result = compile_and_run(src)
      expect(result[:stdout].strip).to eq("25.0\n-1.0\n0.0")
    end

    it 'converts multiple int args to double in a multi-parameter function' do
      src = <<~C
        extern int printf(const char *fmt, ...);
        double add(double a, double b) { return a + b; }
        int main(void) {
          double r = add(3, 4);
          printf("%.1f\\n", r);
          return 0;
        }
      C
      result = compile_and_run(src)
      expect(result[:stdout].strip).to eq('7.0')
    end
  end

  describe '_Generic selection' do
    it 'selects the matching type branch' do
      src = <<~C
        extern int printf(const char *fmt, ...);
        int int_fn(void)    { return 1; }
        int double_fn(void) { return 2; }
        int main(void) {
          double x = 0.0;
          int r = _Generic(x, int: int_fn(), double: double_fn(), default: 0);
          printf("%d\\n", r);
          return 0;
        }
      C
      result = compile_and_run(src)
      expect(result[:stdout].strip).to eq('2')
    end

    it 'falls back to default when no type matches' do
      src = <<~C
        extern int printf(const char *fmt, ...);
        int main(void) {
          int x = 0;
          int r = _Generic(x, double: 99, default: 42);
          printf("%d\\n", r);
          return 0;
        }
      C
      result = compile_and_run(src)
      expect(result[:stdout].strip).to eq('42')
    end
  end
end
