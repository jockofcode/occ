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
require 'occ/codegen/base'
require 'occ/codegen/amd64'
require 'occ/codegen/arm64'
require 'occ/preprocessor'
require 'occ/driver'

RSpec.describe 'Phase 8: Integration' do
  # Compile C source to an executable in a temp dir, run it, return stdout.
  def compile_and_run(src, args: [])
    Dir.mktmpdir do |dir|
      src_path = File.join(dir, 'test.c')
      exe_path = File.join(dir, 'test')

      File.write(src_path, src)

      options = OCC::Driver.parse_options([src_path, '-o', exe_path])
      OCC::Driver.compile_file(src_path, options)

      unless File.exist?(exe_path)
        return { stdout: '', stderr: 'executable not produced', status: 1 }
      end

      stdout, stderr, status = Open3.capture3(exe_path, *args.map(&:to_s))
      { stdout: stdout, stderr: stderr, status: status.exitstatus }
    end
  end

  # Just compile to assembly — can be checked structurally on any platform.
  def compile_to_asm(src)
    OCC::Driver.compile_source(src, '<test>', {})
  end

  # ── Assembly-level checks (platform-independent) ──────────────────────────────

  describe 'assembly output' do
    it 'produces valid assembly for hello world' do
      src = <<~C
        extern int printf(const char *fmt, ...);
        int main(void) {
            printf("Hello, world!\\n");
            return 0;
        }
      C
      asm = compile_to_asm(src)
      expect(asm).not_to be_empty
      expect(asm).to match(/globl.*main/)
      expect(asm).to include('Hello, world!')
    end

    it 'produces assembly for arithmetic operations' do
      src = <<~C
        int add(int a, int b) { return a + b; }
        int main(void) { return add(1, 2); }
      C
      asm = compile_to_asm(src)
      expect(asm).to match(/globl.*add/)
      expect(asm).to match(/globl.*main/)
    end

    it 'produces assembly for a loop' do
      src = <<~C
        int sum(int n) {
            int s = 0;
            for (int i = 0; i < n; i++) { s = s + i; }
            return s;
        }
      C
      asm = compile_to_asm(src)
      expect(asm).to match(/globl.*sum/)
      # Should have loop structure (conditional branch)
      expect(asm).to match(/cbnz|cbz|jne|je|jnz|jz/)
    end

    it 'produces assembly for a recursive function' do
      src = <<~C
        int fact(int n) {
            if (n <= 1) return 1;
            return n * fact(n - 1);
        }
      C
      asm = compile_to_asm(src)
      expect(asm).to match(/globl.*fact/)
    end

    it 'includes string constants in the output' do
      src = 'void f(void){ printf("test string"); }'
      asm = compile_to_asm(src)
      expect(asm).to include('test string')
    end
  end

  # ── Full compilation and execution ───────────────────────────────────────────
  # These tests actually assemble, link, and run the generated binary.
  # They require clang and as to be installed.

  shared_context 'native tools available' do
    before do
      skip 'clang not available' unless system('which clang > /dev/null 2>&1')
      skip 'as not available'    unless system('which as > /dev/null 2>&1')
    end
  end

  describe 'executable output', :slow do
    include_context 'native tools available'

    it 'compiles and runs hello world' do
      src = <<~C
        extern int printf(const char *fmt, ...);
        int main(void) {
            printf("Hello, world!\\n");
            return 0;
        }
      C
      result = compile_and_run(src)
      expect(result[:stdout]).to eq("Hello, world!\n")
      expect(result[:status]).to eq(0)
    end

    it 'returns the correct exit code' do
      src = 'int main(void) { return 42; }'
      result = compile_and_run(src)
      expect(result[:status]).to eq(42)
    end

    it 'computes arithmetic correctly' do
      src = <<~C
        extern int printf(const char *fmt, ...);
        int main(void) {
            int x = 6 * 7;
            printf("%d\\n", x);
            return 0;
        }
      C
      result = compile_and_run(src)
      expect(result[:stdout].strip).to eq('42')
    end

    it 'executes a for loop correctly' do
      src = <<~C
        extern int printf(const char *fmt, ...);
        int main(void) {
            int sum = 0;
            for (int i = 1; i <= 5; i++) {
                sum = sum + i;
            }
            printf("%d\\n", sum);
            return 0;
        }
      C
      result = compile_and_run(src)
      expect(result[:stdout].strip).to eq('15')
    end

    it 'executes conditional logic correctly' do
      src = <<~C
        extern int printf(const char *fmt, ...);
        int main(void) {
            int x = 10;
            if (x > 5) {
                printf("big\\n");
            } else {
                printf("small\\n");
            }
            return 0;
        }
      C
      result = compile_and_run(src)
      expect(result[:stdout].strip).to eq('big')
    end

    it 'calls a user-defined function' do
      src = <<~C
        extern int printf(const char *fmt, ...);
        int double_it(int x) { return x * 2; }
        int main(void) {
            printf("%d\\n", double_it(21));
            return 0;
        }
      C
      result = compile_and_run(src)
      expect(result[:stdout].strip).to eq('42')
    end

    it 'compiles a two-function program' do
      src = <<~C
        extern int printf(const char *fmt, ...);
        int add(int a, int b) { return a + b; }
        int main(void) {
            printf("%d\\n", add(3, 4));
            return 0;
        }
      C
      result = compile_and_run(src)
      expect(result[:stdout].strip).to eq('7')
    end
  end

  # ── -c flag: produce object file ─────────────────────────────────────────────

  describe '-c flag (compile to object)' do
    include_context 'native tools available'

    it 'produces an object file' do
      Dir.mktmpdir do |dir|
        src_path = File.join(dir, 'test.c')
        obj_path = File.join(dir, 'test.o')
        File.write(src_path, 'int f(void){ return 1; }')

        options = OCC::Driver.parse_options(['-c', src_path, '-o', obj_path])
        OCC::Driver.compile_file(src_path, options)

        expect(File.exist?(obj_path)).to be(true)
        expect(File.size(obj_path)).to be > 0
      end
    end
  end
end
