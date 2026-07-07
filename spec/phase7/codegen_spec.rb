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

RSpec.describe 'Phase 7: Code Generation' do
  NATIVE_ARCH = `uname -m`.strip
  NATIVE_OS   = `uname -s`.strip

  def compile_to_asm(src, backend: :native)
    tokens  = OCC::Lexer.new(src, '<test>').tokenize
    ast     = OCC::Parser.new(tokens).parse
    sa      = OCC::Semantic.new
    sa.analyze(ast)
    ir      = OCC::IR::Builder.new.build(ast)

    target = case backend
             when :native
               NATIVE_ARCH == 'arm64' ? :arm64_macos : :amd64_linux
             when :amd64 then :amd64_linux
             when :arm64 then :arm64_macos
             end

    gen = case target
          when :arm64_macos
            OCC::Codegen::ARM64.new(ir, target: :arm64_macos)
          else
            OCC::Codegen::AMD64.new(ir, target: target)
          end

    gen.generate
  end

  # ── Structure checks (all platforms) ────────────────────────────────────────

  describe 'output structure' do
    it 'produces non-empty assembly' do
      asm = compile_to_asm('int main(void){ return 0; }')
      expect(asm).not_to be_empty
    end

    it 'exports the main symbol' do
      asm = compile_to_asm('int main(void){ return 0; }')
      expect(asm).to match(/globl.*main/)
    end

    it 'contains a function label for main' do
      asm = compile_to_asm('int main(void){ return 0; }')
      expect(asm).to match(/_?main:/)
    end

    it 'contains a return instruction' do
      asm = compile_to_asm('int main(void){ return 0; }')
      # ARM64 uses 'ret', AMD64 uses 'retq'
      expect(asm).to match(/\bret/)
    end

    it 'includes string data for string literals' do
      asm = compile_to_asm('void f(void){ printf("hello"); }')
      expect(asm).to include('hello')
    end

    it 'exports multiple functions' do
      src = 'int f(void){ return 1; } int g(void){ return 2; }'
      asm = compile_to_asm(src)
      expect(asm).to match(/globl.*_?f/)
      expect(asm).to match(/globl.*_?g/)
    end
  end

  # ── AMD64-specific checks ────────────────────────────────────────────────────

  describe 'AMD64 backend' do
    def amd64_asm(src) = compile_to_asm(src, backend: :amd64)

    it 'generates prologue with pushq %rbp' do
      asm = amd64_asm('int main(void){ return 0; }')
      expect(asm).to include('pushq %rbp')
    end

    it 'generates movq %rsp, %rbp' do
      asm = amd64_asm('int main(void){ return 0; }')
      expect(asm).to include('movq %rsp, %rbp')
    end

    it 'generates callq for function calls' do
      asm = amd64_asm('extern int g(int); void f(void){ g(1); }')
      expect(asm).to match(/callq/)
    end

    it 'passes first argument in %rdi' do
      asm = amd64_asm('extern int g(int); void f(void){ g(42); }')
      expect(asm).to include('%rdi')
    end

    it 'uses addq for addition' do
      asm = amd64_asm('int f(void){ return 1 + 2; }')
      expect(asm).to include('addq')
    end

    it 'uses subq for subtraction' do
      asm = amd64_asm('int f(void){ return 3 - 1; }')
      expect(asm).to include('subq')
    end

    it 'uses imulq for multiplication' do
      asm = amd64_asm('int f(void){ return 2 * 3; }')
      expect(asm).to include('imulq')
    end

    it 'uses cmpq + sete for equality' do
      asm = amd64_asm('int f(void){ return 1 == 1; }')
      expect(asm).to include('cmpq')
      expect(asm).to include('sete')
    end

    it 'generates if/else with jumps' do
      asm = amd64_asm('int f(int x){ if (x) { return 1; } return 0; }')
      expect(asm).to match(/jne|je|jnz|jz/)
    end

    it 'loads string address with leaq' do
      asm = amd64_asm('void f(void){ printf("hi"); }')
      expect(asm).to include('leaq')
    end
  end

  # ── ARM64-specific checks ────────────────────────────────────────────────────

  describe 'ARM64 backend' do
    def arm64_asm(src) = compile_to_asm(src, backend: :arm64)

    it 'generates stp x29, x30 prologue' do
      asm = arm64_asm('int main(void){ return 0; }')
      expect(asm).to include('stp x29, x30')
    end

    it 'generates mov x29, sp' do
      asm = arm64_asm('int main(void){ return 0; }')
      expect(asm).to include('mov x29, sp')
    end

    it 'generates bl for function calls' do
      asm = arm64_asm('extern int g(int); void f(void){ g(1); }')
      expect(asm).to include('bl')
    end

    it 'passes first argument in x0' do
      asm = arm64_asm('extern int g(int); void f(void){ g(42); }')
      expect(asm).to include('x0')
    end

    it 'uses add for addition' do
      asm = arm64_asm('int f(void){ return 1 + 2; }')
      expect(asm).to include('add')
    end

    it 'uses mul for multiplication' do
      asm = arm64_asm('int f(void){ return 2 * 3; }')
      expect(asm).to include('mul')
    end

    it 'uses cmp + cset for comparisons' do
      asm = arm64_asm('int f(void){ return 1 == 1; }')
      expect(asm).to include('cmp')
      expect(asm).to include('cset')
    end

    it 'generates conditional branch instruction' do
      asm = arm64_asm('int f(int x){ if (x) { return 1; } return 0; }')
      expect(asm).to match(/cbnz|cbz/)
    end

    it 'loads string address with adrp + add' do
      asm = arm64_asm('void f(void){ printf("hi"); }')
      expect(asm).to include('adrp')
    end

    it 'includes .p2align directive for alignment' do
      asm = arm64_asm('int main(void){ return 0; }')
      expect(asm).to include('.p2align')
    end
  end
end
