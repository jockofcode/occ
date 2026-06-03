# frozen_string_literal: true

require 'occ/error'
require 'occ/source_location'
require 'occ/preprocessor'

RSpec.describe OCC::Preprocessor do
  def preprocess(src, defines: {}, include_paths: [])
    pp = OCC::Preprocessor.new(src, '<test>', defines: defines, include_paths: include_paths)
    pp.process.strip
  end

  # ── Object-like macros ────────────────────────────────────────────────────────

  describe '#define (object-like)' do
    it 'replaces a simple macro' do
      result = preprocess("#define FOO 42\nint x = FOO;")
      expect(result).to include('42')
      expect(result).not_to include('FOO')
    end

    it 'replaces a multi-token macro' do
      result = preprocess("#define MAX_SIZE 1024\nchar buf[MAX_SIZE];")
      expect(result).to include('1024')
    end

    it '#undef removes the macro' do
      result = preprocess("#define X 1\n#undef X\nint a = X;")
      expect(result).to include('X')  # X is no longer expanded
    end
  end

  # ── Function-like macros ──────────────────────────────────────────────────────

  describe '#define (function-like)' do
    it 'expands a single-argument macro' do
      result = preprocess("#define DOUBLE(x) x + x\nint a = DOUBLE(5);")
      expect(result).to include('5 + 5')
    end

    it 'expands a two-argument macro' do
      result = preprocess("#define ADD(a, b) a + b\nint c = ADD(1, 2);")
      expect(result).to include('1 + 2')
    end

    it 'handles stringification with #' do
      result = preprocess(%{#define STR(x) #x\nchar *s = STR(hello);})
      expect(result).to include('"hello"')
    end
  end

  # ── Predefined macros ─────────────────────────────────────────────────────────

  describe 'predefined macros' do
    it '__STDC__ expands to 1' do
      result = preprocess('int a = __STDC__;')
      expect(result).to include('1')
    end

    it '__FILE__ expands to the filename' do
      result = preprocess('const char *f = __FILE__;')
      expect(result).to include('<test>')
    end

    it '__LINE__ expands to the current line number' do
      result = preprocess("int a;\nint b = __LINE__;")
      expect(result).to match(/\d+/)
    end
  end

  # ── Conditional compilation ───────────────────────────────────────────────────

  describe '#ifdef / #ifndef' do
    it '#ifdef includes the block when defined' do
      src = <<~C
        #define DEBUG 1
        #ifdef DEBUG
        int debug = 1;
        #endif
      C
      result = preprocess(src)
      expect(result).to include('debug')
    end

    it '#ifdef excludes the block when not defined' do
      src = <<~C
        #ifdef UNDEFINED_MACRO
        int secret = 99;
        #endif
      C
      result = preprocess(src)
      expect(result).not_to include('secret')
    end

    it '#ifndef includes the block when not defined' do
      src = <<~C
        #ifndef MISSING
        int visible = 1;
        #endif
      C
      result = preprocess(src)
      expect(result).to include('visible')
    end

    it '#ifndef excludes the block when defined' do
      src = <<~C
        #define PRESENT 1
        #ifndef PRESENT
        int hidden = 1;
        #endif
      C
      result = preprocess(src)
      expect(result).not_to include('hidden')
    end
  end

  describe '#if / #elif / #else / #endif' do
    it '#if 1 includes the block' do
      result = preprocess("#if 1\nint yes = 1;\n#endif")
      expect(result).to include('yes')
    end

    it '#if 0 excludes the block' do
      result = preprocess("#if 0\nint no = 1;\n#endif")
      expect(result).not_to include('no')
    end

    it '#else is taken when #if is false' do
      src = "#if 0\nint a;\n#else\nint b;\n#endif"
      result = preprocess(src)
      expect(result).to include('b')
      expect(result).not_to include('int a')
    end

    it '#elif is taken when its condition is true' do
      src = "#if 0\nint a;\n#elif 1\nint b;\n#else\nint c;\n#endif"
      result = preprocess(src)
      expect(result).to include('b')
      expect(result).not_to include('int a')
      expect(result).not_to include('int c')
    end

    it 'nested conditionals work correctly' do
      src = <<~C
        #define A 1
        #if defined(A)
          #if 0
          int inner_no;
          #else
          int inner_yes;
          #endif
        #endif
      C
      result = preprocess(src)
      expect(result).to include('inner_yes')
      expect(result).not_to include('inner_no')
    end

    it 'evaluates defined() in #if expressions' do
      src = "#define FOO\n#if defined(FOO)\nint x;\n#endif"
      result = preprocess(src)
      expect(result).to include('int x')
    end

    it 'evaluates complex arithmetic in #if' do
      result = preprocess("#if 2 + 2 == 4\nint yes;\n#endif")
      expect(result).to include('yes')
    end
  end

  # ── -D command-line defines ───────────────────────────────────────────────────

  describe '-D defines' do
    it 'expands a macro passed via defines:' do
      result = preprocess('int x = VERSION;', defines: { 'VERSION' => '3' })
      expect(result).to include('3')
    end

    it 'a bare define (no value) still defines the macro' do
      result = preprocess("#ifdef FEATURE\nint f;\n#endif", defines: { 'FEATURE' => nil })
      expect(result).to include('f')
    end
  end

  # ── #include ──────────────────────────────────────────────────────────────────

  describe '#include' do
    it 'includes a local file' do
      Dir.mktmpdir do |dir|
        header = File.join(dir, 'my_header.h')
        File.write(header, "int from_header = 1;\n")
        src = %{#include "my_header.h"\nint main() {}\n}
        pp = OCC::Preprocessor.new(src, File.join(dir, 'test.c'),
                                   include_paths: [dir])
        result = pp.process.strip
        expect(result).to include('from_header')
      end
    end

    it 'includes a file from an include path' do
      Dir.mktmpdir do |dir|
        header = File.join(dir, 'inc.h')
        File.write(header, "int value = 42;\n")
        result = preprocess(%{#include <inc.h>\n}, include_paths: [dir])
        expect(result).to include('42')
      end
    end

    it 'raises PreprocError for a missing include' do
      expect {
        preprocess('#include "no_such_file.h"')
      }.to raise_error(OCC::PreprocError, /cannot find/)
    end

    it 'detects recursive includes' do
      Dir.mktmpdir do |dir|
        header = File.join(dir, 'recursive.h')
        File.write(header, "#include \"recursive.h\"\n")
        expect {
          preprocess(%{#include "recursive.h"\n},
                     include_paths: [dir])
        }.to raise_error(OCC::PreprocError, /recursive include/)
      end
    end
  end

  # ── #error ───────────────────────────────────────────────────────────────────

  describe '#error' do
    it 'raises PreprocError when active' do
      expect {
        preprocess('#error this is an error message')
      }.to raise_error(OCC::PreprocError, /this is an error message/)
    end

    it 'does not raise when inside a false conditional' do
      expect {
        preprocess("#if 0\n#error hidden\n#endif")
      }.not_to raise_error
    end
  end

  # ── #pragma once ──────────────────────────────────────────────────────────────

  describe '#pragma once' do
    it 'prevents a file from being included twice' do
      Dir.mktmpdir do |dir|
        header = File.join(dir, 'once.h')
        File.write(header, "#pragma once\nint x = 1;\n")
        src = "#include <once.h>\n#include <once.h>\n"
        result = preprocess(src, include_paths: [dir])
        # Should only have one definition
        expect(result.scan('int x').length).to eq(1)
      end
    end
  end
end
