# frozen_string_literal: true

RSpec.describe 'Phase 1: Driver' do
  describe 'reading and printing files' do
    it 'compiles a source file and prints assembly to stdout' do
      source = "int main(void) { return 0; }\n"

      with_c_file(source) do |path|
        result = run_occ(path)

        expect(result[:stdout]).to match(/globl.*main/)
        expect(result[:status]).to eq(0)
      end
    end

    it 'handles empty files without crashing' do
      with_c_file('') do |path|
        result = run_occ(path)
        expect(result[:status]).to eq(0)
      end
    end

    it 'compiles a multi-function file' do
      source = <<~C
        int add(int a, int b) { return a + b; }
        int main(void) { return add(1, 2); }
      C
      with_c_file(source) do |path|
        result = run_occ(path)
        expect(result[:stdout]).to match(/globl.*add/)
        expect(result[:stdout]).to match(/globl.*main/)
        expect(result[:status]).to eq(0)
      end
    end
  end

  describe 'error handling' do
    it 'exits non-zero when no files are given' do
      result = run_occ
      expect(result[:status]).not_to eq(0)
      expect(result[:stderr]).to include('no input files')
    end

    it 'exits non-zero for a nonexistent file' do
      result = run_occ('/nonexistent/path/missing.c')
      expect(result[:status]).not_to eq(0)
      expect(result[:stderr]).to include('No such file or directory')
    end
  end

  describe 'option parsing' do
    it 'parses -o flag' do
      opts = OCC::Driver.parse_options(['-o', 'out', 'file.c'])
      expect(opts[:output]).to eq('out')
      expect(opts[:files]).to eq(['file.c'])
    end

    it 'parses -c flag' do
      opts = OCC::Driver.parse_options(['-c', 'file.c'])
      expect(opts[:compile_only]).to be true
    end

    it 'parses -I flag (attached)' do
      opts = OCC::Driver.parse_options(['-I/usr/include', 'file.c'])
      expect(opts[:include_paths]).to eq(['/usr/include'])
    end

    it 'parses -I flag (separate)' do
      opts = OCC::Driver.parse_options(['-I', '/usr/include', 'file.c'])
      expect(opts[:include_paths]).to eq(['/usr/include'])
    end

    it 'parses -D flag (attached)' do
      opts = OCC::Driver.parse_options(['-DDEBUG=1', 'file.c'])
      expect(opts[:defines]).to eq(['DEBUG=1'])
    end

    it 'parses multiple files' do
      opts = OCC::Driver.parse_options(['a.c', 'b.c'])
      expect(opts[:files]).to eq(['a.c', 'b.c'])
    end
  end
end
