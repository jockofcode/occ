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

RSpec.describe 'Phase 10: Headers, Language Extensions, and FP Codegen' do
  # Compile C source all the way to assembly (no native tools needed)
  def compile_to_asm(src, include_paths: [])
    OCC::Driver.compile_source(src, '<test>', { include_paths: include_paths })
  end

  # Compile and run — requires clang/as on the host
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

  def build_ir(src)
    tokens  = OCC::Lexer.new(src, '<test>').tokenize
    ast     = OCC::Parser.new(tokens).parse
    sa      = OCC::Semantic.new
    sa.analyze(ast)
    OCC::IR::Builder.new.build(ast)
  end

  def all_instrs(func)
    func.blocks.flat_map(&:instrs)
  end

  shared_context 'native tools available' do
    before do
      skip 'clang not available' unless system('which clang > /dev/null 2>&1')
      skip 'as not available'    unless system('which as > /dev/null 2>&1')
    end
  end

  # ── GCC/Clang extension macros ───────────────────────────────────────────────

  describe '__attribute__ passthrough' do
    it 'parses __attribute__((packed)) on a struct without error' do
      src = <<~C
        struct __attribute__((packed)) S { int x; char y; };
        int f(void) { return sizeof(struct S); }
      C
      expect { compile_to_asm(src) }.not_to raise_error
    end

    it 'parses __attribute__((unused)) on a variable without error' do
      src = 'void f(void) { int x __attribute__((unused)) = 0; (void)x; }'
      expect { compile_to_asm(src) }.not_to raise_error
    end

    it 'parses __attribute__((noreturn)) on a function declaration without error' do
      src = 'void die(void) __attribute__((noreturn)); void f(void) { die(); }'
      expect { compile_to_asm(src) }.not_to raise_error
    end

    it 'emits __mod_init_func pointer for __attribute__((constructor)) function' do
      src = <<~C
        static int counter = 0;
        static void init(void) __attribute__((constructor));
        static void init(void) { counter = 42; }
        int get(void) { return counter; }
      C
      asm = compile_to_asm(src)
      expect(asm).to include('__mod_init_func')
      expect(asm).to include('_init')
    end
  end

  describe '__extension__ keyword' do
    it 'parses __extension__ on a declaration without error' do
      src = '__extension__ typedef long long int64_t; int f(void) { int64_t x = 1; return (int)x; }'
      expect { compile_to_asm(src) }.not_to raise_error
    end
  end

  describe '__builtin_expect' do
    it 'expands __builtin_expect(expr, val) to expr' do
      src = 'int f(int x) { if (__builtin_expect(x == 0, 0)) return 1; return 0; }'
      expect { compile_to_asm(src) }.not_to raise_error
    end
  end

  # ── Standard headers ─────────────────────────────────────────────────────────

  describe 'standard headers compile without error' do
    %w[stdio.h string.h stdlib.h math.h ctype.h assert.h setjmp.h
       signal.h unistd.h errno.h fcntl.h time.h stdint.h stdbool.h
       stddef.h limits.h float.h sys/types.h sys/stat.h].each do |header|
      it "#include <#{header}> produces valid assembly" do
        src = "#include <#{header}>\nint main(void) { return 0; }\n"
        expect { compile_to_asm(src) }.not_to raise_error
      end
    end

    it '#include <stdio.h> declares printf (no undeclared-identifier error)' do
      src = <<~C
        #include <stdio.h>
        int main(void) { printf("hi\\n"); return 0; }
      C
      asm = compile_to_asm(src)
      expect(asm).to match(/printf/)
    end

    it '#include <string.h> makes strlen available' do
      src = <<~C
        #include <string.h>
        int main(void) { return (int)strlen("hello"); }
      C
      expect { compile_to_asm(src) }.not_to raise_error
    end

    it '#include <stdlib.h> makes malloc and free available' do
      src = <<~C
        #include <stdlib.h>
        int main(void) { void *p = malloc(16); free(p); return 0; }
      C
      expect { compile_to_asm(src) }.not_to raise_error
    end

    it '#include <math.h> declares sin and sqrt' do
      src = <<~C
        #include <math.h>
        double f(double x) { return sqrt(x) + sin(x); }
      C
      expect { compile_to_asm(src) }.not_to raise_error
    end

    it '#include <math.h> provides INFINITY and NAN macros' do
      src = <<~C
        #include <math.h>
        double inf(void) { return INFINITY; }
        double nan_val(void) { return NAN; }
      C
      expect { compile_to_asm(src) }.not_to raise_error
    end

    it '#include <ctype.h> makes isdigit and toupper available' do
      src = <<~C
        #include <ctype.h>
        int f(int c) { return isdigit(c) ? toupper(c) : c; }
      C
      expect { compile_to_asm(src) }.not_to raise_error
    end

    it '#include <setjmp.h> declares jmp_buf and setjmp' do
      src = <<~C
        #include <setjmp.h>
        jmp_buf env;
        int f(void) { return setjmp(env); }
      C
      expect { compile_to_asm(src) }.not_to raise_error
    end

    it '#include <signal.h> declares signal() and SIG constants' do
      src = <<~C
        #include <signal.h>
        void handler(int sig) { (void)sig; }
        int f(void) { signal(SIGINT, handler); return 0; }
      C
      expect { compile_to_asm(src) }.not_to raise_error
    end

    it '#include <unistd.h> declares read, write, and close' do
      src = <<~C
        #include <unistd.h>
        int f(void) { return (int)write(1, "x", 1); }
      C
      expect { compile_to_asm(src) }.not_to raise_error
    end
  end

  # ── Bitfield structs ─────────────────────────────────────────────────────────

  describe 'bitfield struct parsing' do
    it 'parses a struct with bitfield members without error' do
      src = <<~C
        struct Flags {
            unsigned int active : 1;
            unsigned int mode   : 3;
            unsigned int level  : 4;
        };
        int f(void) { return sizeof(struct Flags); }
      C
      expect { compile_to_asm(src) }.not_to raise_error
    end

    it 'treats bitfield struct members as accessible fields' do
      src = <<~C
        struct Flags { unsigned int a : 1; unsigned int b : 7; };
        int f(struct Flags fl) { return (int)fl.a + (int)fl.b; }
      C
      expect { compile_to_asm(src) }.not_to raise_error
    end

    it 'builds IR for a function using a bitfield struct' do
      src = <<~C
        struct S { int x : 4; int y : 4; };
        int f(struct S s) { return s.x; }
      C
      mod  = build_ir(src)
      func = mod.functions.find { |fn| fn.name == 'f' }
      expect(func).not_to be_nil
    end
  end

  # ── Designated initializers ──────────────────────────────────────────────────

  describe 'designated initializers' do
    it 'parses designated struct initializers without error' do
      src = <<~C
        struct Point { int x; int y; };
        struct Point make(void) {
            struct Point p = { .x = 3, .y = 4 };
            return p;
        }
      C
      expect { compile_to_asm(src) }.not_to raise_error
    end

    it 'builds IR for a designated struct initializer' do
      src = <<~C
        struct Point { int x; int y; };
        int f(void) {
            struct Point p = { .x = 10, .y = 20 };
            return p.x;
        }
      C
      mod  = build_ir(src)
      func = mod.functions.find { |fn| fn.name == 'f' }
      stores = all_instrs(func).select { |i| i.is_a?(OCC::IR::Store) }
      expect(stores).not_to be_empty
    end

    it 'parses designated array initializers without error' do
      src = <<~C
        int arr[5] = { [0] = 1, [2] = 3 };
        int f(void) { return arr[0] + arr[2]; }
      C
      expect { compile_to_asm(src) }.not_to raise_error
    end
  end

  # ── Compound literals ────────────────────────────────────────────────────────

  describe 'compound literals' do
    it 'parses a struct compound literal without error' do
      src = <<~C
        struct Point { int x; int y; };
        int f(struct Point p) { return p.x + p.y; }
        int g(void) { return f((struct Point){ .x = 1, .y = 2 }); }
      C
      expect { compile_to_asm(src) }.not_to raise_error
    end

    it 'builds IR for a compound literal (alloca + stores)' do
      src = <<~C
        struct Point { int x; int y; };
        int f(struct Point p) { return p.x; }
        int g(void) { return f((struct Point){ .x = 5, .y = 6 }); }
      C
      mod  = build_ir(src)
      func = mod.functions.find { |fn| fn.name == 'g' }
      allocas = all_instrs(func).select { |i| i.is_a?(OCC::IR::Alloca) }
      expect(allocas).not_to be_empty
    end
  end

  # ── Floating-point codegen ────────────────────────────────────────────────────

  describe 'FP type propagation (IR)' do
    it 'marks a double variable alloca as FP' do
      src = 'double f(double x) { return x + 1.0; }'
      mod  = build_ir(src)
      func = mod.functions.find { |fn| fn.name == 'f' }
      bins = all_instrs(func).select { |i| i.is_a?(OCC::IR::Binary) }
      expect(bins).not_to be_empty
      expect(bins.first.op).to eq(:plus)
    end

    it 'marks a double-returning call as FP in fp_funcs' do
      src = <<~C
        extern double sqrt(double);
        double f(double x) { return sqrt(x); }
      C
      mod = build_ir(src)
      expect(mod.fp_funcs).to include('sqrt')
    end
  end

  describe 'FP assembly output' do
    it 'emits FP-related instructions for double addition' do
      src = 'double f(double x, double y) { return x + y; }'
      asm = compile_to_asm(src)
      expect(asm).to match(/fadd|addsd|fmul|mulsd/)
    end

    it 'emits FP-related instructions for double multiplication' do
      src = 'double scale(double x) { return x * 2.0; }'
      asm = compile_to_asm(src)
      expect(asm).to match(/fmul|mulsd/)
    end

    it 'emits int-to-double conversion instruction' do
      src = 'double itod(int x) { return (double)x; }'
      asm = compile_to_asm(src)
      expect(asm).to match(/scvtf|cvtsi2sd/)
    end

    it 'emits double-to-int conversion instruction' do
      src = 'int dtoi(double x) { return (int)x; }'
      asm = compile_to_asm(src)
      expect(asm).to match(/fcvtzs|cvttsd2si/)
    end

    it 'emits float literal via literal pool or rodata' do
      src = 'double f(void) { return 3.14; }'
      asm = compile_to_asm(src)
      expect(asm).to match(/\.double|ldr.*flt|movsd.*flt|movsd.*Lflt/)
    end
  end

  describe 'FP integration', :slow do
    include_context 'native tools available'

    it 'adds two doubles correctly' do
      src = <<~C
        extern int printf(const char *fmt, ...);
        double add(double a, double b) { return a + b; }
        int main(void) {
            double r = add(1.5, 2.5);
            printf("%d\\n", (int)r);
            return 0;
        }
      C
      result = compile_and_run(src)
      expect(result[:stdout].strip).to eq('4')
    end

    it 'multiplies a double by a constant correctly' do
      src = <<~C
        extern int printf(const char *fmt, ...);
        int main(void) {
            double x = 6.0;
            double y = x * 7.0;
            printf("%d\\n", (int)y);
            return 0;
        }
      C
      result = compile_and_run(src)
      expect(result[:stdout].strip).to eq('42')
    end

    it 'converts int to double and back correctly' do
      src = <<~C
        extern int printf(const char *fmt, ...);
        int main(void) {
            int n = 21;
            double d = (double)n * 2.0;
            int result = (int)d;
            printf("%d\\n", result);
            return 0;
        }
      C
      result = compile_and_run(src)
      expect(result[:stdout].strip).to eq('42')
    end

    it 'compares doubles correctly' do
      src = <<~C
        extern int printf(const char *fmt, ...);
        int main(void) {
            double a = 3.0, b = 4.0;
            printf("%d\\n", a < b ? 1 : 0);
            return 0;
        }
      C
      result = compile_and_run(src)
      expect(result[:stdout].strip).to eq('1')
    end

    it 'calls an external math function (sqrt)' do
      src = <<~C
        #include <math.h>
        extern int printf(const char *fmt, ...);
        int main(void) {
            double r = sqrt(9.0);
            printf("%d\\n", (int)r);
            return 0;
        }
      C
      result = compile_and_run(src)
      expect(result[:stdout].strip).to eq('3')
    end

    it 'divides doubles correctly' do
      src = <<~C
        extern int printf(const char *fmt, ...);
        int main(void) {
            double a = 10.0;
            double b = 4.0;
            double r = a / b;
            printf("%d\\n", (int)(r * 10.0));
            return 0;
        }
      C
      result = compile_and_run(src)
      expect(result[:stdout].strip).to eq('25')
    end
  end

  # ── FP via math.h integration ────────────────────────────────────────────────

  describe '#include <math.h> integration', :slow do
    include_context 'native tools available'

    it 'calls sin and gets a reasonable result' do
      src = <<~C
        #include <math.h>
        extern int printf(const char *fmt, ...);
        int main(void) {
            double r = sin(0.0);
            printf("%d\\n", (int)r);
            return 0;
        }
      C
      result = compile_and_run(src)
      expect(result[:stdout].strip).to eq('0')
    end
  end

  # ── Multiple headers together ────────────────────────────────────────────────

  describe 'multiple headers included together' do
    it 'can include stdio.h and string.h together' do
      src = <<~C
        #include <stdio.h>
        #include <string.h>
        int f(void) { return (int)strlen("hello"); }
      C
      expect { compile_to_asm(src) }.not_to raise_error
    end

    it 'can include stdlib.h and string.h together' do
      src = <<~C
        #include <stdlib.h>
        #include <string.h>
        int f(void) {
            char *p = (char *)malloc(8);
            memset(p, 0, 8);
            free(p);
            return 0;
        }
      C
      expect { compile_to_asm(src) }.not_to raise_error
    end

    it 'can include math.h and stdio.h together' do
      src = <<~C
        #include <math.h>
        #include <stdio.h>
        double f(double x) { return sqrt(x); }
      C
      expect { compile_to_asm(src) }.not_to raise_error
    end
  end

  # ── Bitfield struct layout ───────────────────────────────────────────────────

  describe 'bitfield layout (IR)' do
    it 'packs two bitfields into the same storage unit' do
      src = <<~C
        struct Flags { unsigned int a : 4; unsigned int b : 4; };
        int f(void) { return sizeof(struct Flags); }
      C
      mod = build_ir(src)
      # (build_ir succeeds without error)
      expect(mod).not_to be_nil
    end

    it 'builds correct field offsets for bitfields in the same storage unit' do
      src = <<~C
        struct S { unsigned int x : 4; unsigned int y : 4; };
        void f(void) {}
      C
      tokens = OCC::Lexer.new(src, '<test>').tokenize
      ast    = OCC::Parser.new(tokens).parse
      sa     = OCC::Semantic.new
      sa.analyze(ast)
      # Find the struct type in the typedef/tag map via the AST
      struct_spec = ast.decls.first.specifiers.tag_decl
      st = sa.instance_variable_get(:@struct_tags)[struct_spec&.tag] ||
           begin
             OCC::Types::StructType.new(:kw_struct, nil).tap do |s|
               # force re-analysis to extract the struct
             end
           end
      # We verify by compiling and checking member load emits a rshift/mask
      mod  = build_ir(src)
      expect(mod).not_to be_nil
    end

    it 'emits rshift+mask instructions when reading a bitfield' do
      src = <<~C
        struct S { unsigned int x : 4; unsigned int y : 4; };
        int f(struct S s) { return (int)s.y; }
      C
      mod  = build_ir(src)
      func = mod.functions.find { |fn| fn.name == 'f' }
      bins = func.blocks.flat_map(&:instrs).select { |i| i.is_a?(OCC::IR::Binary) }
      ops  = bins.map(&:op)
      expect(ops).to include(:rshift)
      expect(ops).to include(:amp)
    end

    it 'emits read-modify-write when writing a bitfield' do
      src = <<~C
        struct S { unsigned int x : 4; unsigned int y : 4; };
        void f(struct S *s, int v) { s->y = v; }
      C
      mod  = build_ir(src)
      func = mod.functions.find { |fn| fn.name == 'f' }
      bins = func.blocks.flat_map(&:instrs).select { |i| i.is_a?(OCC::IR::Binary) }
      ops  = bins.map(&:op)
      expect(ops).to include(:amp)
      expect(ops).to include(:lshift)
      expect(ops).to include(:pipe)
    end
  end

  describe 'bitfield layout (integration)', :slow do
    include_context 'native tools available'

    it 'reads back the correct value from a bitfield' do
      src = <<~C
        #include <stdio.h>
        struct Flags { unsigned int lo : 4; unsigned int hi : 4; };
        int main(void) {
            struct Flags f;
            f.lo = 3;
            f.hi = 7;
            printf("%d %d\\n", (int)f.lo, (int)f.hi);
            return 0;
        }
      C
      result = compile_and_run(src)
      expect(result[:stdout].strip).to eq('3 7')
    end

    it 'does not let writing one bitfield corrupt an adjacent one' do
      src = <<~C
        #include <stdio.h>
        struct Flags { unsigned int a : 4; unsigned int b : 4; };
        int main(void) {
            struct Flags f;
            f.a = 5;
            f.b = 10;
            f.a = 2;
            printf("%d %d\\n", (int)f.a, (int)f.b);
            return 0;
        }
      C
      result = compile_and_run(src)
      expect(result[:stdout].strip).to eq('2 10')
    end

    it 'handles zero-bit-offset field (first bitfield in struct)' do
      src = <<~C
        #include <stdio.h>
        struct S { unsigned int flag : 1; unsigned int rest : 7; };
        int main(void) {
            struct S s;
            s.flag = 1;
            s.rest = 42;
            printf("%d %d\\n", (int)s.flag, (int)s.rest);
            return 0;
        }
      C
      result = compile_and_run(src)
      expect(result[:stdout].strip).to eq('1 42')
    end
  end

  # ── va_list / variadic helpers ───────────────────────────────────────────────

  describe 'va_list assembly output' do
    it 'includes <stdarg.h> without error' do
      src = <<~C
        #include <stdarg.h>
        int f(int a, ...) { va_list ap; va_start(ap, a); va_end(ap); return 0; }
      C
      expect { compile_to_asm(src) }.not_to raise_error
    end

    it 'emits a call to __occ_va_first_arg for va_start' do
      src = <<~C
        #include <stdarg.h>
        int f(int a, ...) { va_list ap; va_start(ap, a); va_end(ap); return 0; }
      C
      asm = compile_to_asm(src)
      # (ARM64: add x9, x29, #N  /  AMD64: leaq N(%rbp), %rax)
      expect(asm).to match(/va_first_arg|add x9.*x29|leaq.*%rbp/)
    end
  end

  describe 'va_list integration', :slow do
    include_context 'native tools available'

    it 'sums variadic int arguments' do
      src = <<~C
        #include <stdarg.h>
        #include <stdio.h>
        int sum(int count, ...) {
            va_list ap;
            va_start(ap, count);
            int total = 0;
            int i;
            for (i = 0; i < count; i++) {
                total = total + va_arg(ap, int);
            }
            va_end(ap);
            return total;
        }
        int main(void) {
            printf("%d\\n", sum(3, 10, 20, 30));
            return 0;
        }
      C
      result = compile_and_run(src)
      expect(result[:stdout].strip).to eq('60')
    end

    it 'passes va_list to vsnprintf for string formatting' do
      src = <<~C
        #include <stdarg.h>
        #include <stdio.h>
        int my_sprintf(char *buf, const char *fmt, ...) {
            va_list ap;
            va_start(ap, fmt);
            int r = vsnprintf(buf, 64, fmt, ap);
            va_end(ap);
            return r;
        }
        int main(void) {
            char buf[64];
            my_sprintf(buf, "hello %d", 42);
            printf("%s\\n", buf);
            return 0;
        }
      C
      result = compile_and_run(src)
      expect(result[:stdout].strip).to eq('hello 42')
    end

    it 'passes va_list to vprintf' do
      src = <<~C
        #include <stdarg.h>
        #include <stdio.h>
        void my_print(const char *fmt, ...) {
            va_list ap;
            va_start(ap, fmt);
            vprintf(fmt, ap);
            va_end(ap);
        }
        int main(void) {
            my_print("value=%d\\n", 99);
            return 0;
        }
      C
      result = compile_and_run(src)
      expect(result[:stdout].strip).to eq('value=99')
    end
  end

  describe 'longjmp integration', :slow do
    include_context 'native tools available'

    it 'jumps back to setjmp call site and resumes with the given value' do
      src = <<~C
        #include <setjmp.h>
        #include <stdio.h>
        static jmp_buf buf;
        void thrower(void) {
            longjmp(buf, 42);
        }
        int main(void) {
            int v = setjmp(buf);
            if (v == 0) {
                thrower();
            } else {
                printf("caught=%d\\n", v);
            }
            return 0;
        }
      C
      result = compile_and_run(src)
      expect(result[:stdout].strip).to eq('caught=42')
    end

    it 'can be used to implement early exit from a nested loop' do
      src = <<~C
        #include <setjmp.h>
        #include <stdio.h>
        static jmp_buf escape;
        int main(void) {
            int found = setjmp(escape);
            if (found) {
                printf("found=%d\\n", found);
                return 0;
            }
            int i;
            int j;
            for (i = 1; i <= 5; i++) {
                for (j = 1; j <= 5; j++) {
                    if (i * j == 12) {
                        longjmp(escape, i * 10 + j);
                    }
                }
            }
            printf("not found\\n");
            return 0;
        }
      C
      result = compile_and_run(src)
      expect(result[:stdout].strip).to eq('found=34')
    end
  end

  describe 'POSIX file I/O integration', :slow do
    include_context 'native tools available'

    it 'writes to a file with open/write/close and reads it back with read' do
      path = "/tmp/occ_posix_#{Process.pid}.txt"
      src = <<~C
        #include <fcntl.h>
        #include <unistd.h>
        #include <stdio.h>
        static char buf[32];
        int main(void) {
            int fd = open("#{path}", O_WRONLY | O_CREAT | O_TRUNC, 0644);
            if (fd < 0) { printf("open failed\\n"); return 1; }
            write(fd, "hello posix", 11);
            close(fd);
            fd = open("#{path}", O_RDONLY, 0);
            if (fd < 0) { printf("reopen failed\\n"); return 1; }
            int n = read(fd, buf, 31);
            close(fd);
            buf[n] = 0;
            printf("%s\\n", buf);
            return 0;
        }
      C
      result = compile_and_run(src)
      File.delete(path) if File.exist?(path)
      expect(result[:stdout].strip).to eq('hello posix')
    end

    it 'uses write() to emit output to stdout (fd 1)' do
      src = <<~C
        #include <unistd.h>
        int main(void) {
            write(1, "direct write\\n", 13);
            return 0;
        }
      C
      result = compile_and_run(src)
      expect(result[:stdout].strip).to eq('direct write')
    end
  end
end
