# frozen_string_literal: true

require 'open3'
require 'tmpdir'
require 'fileutils'

# Phase 12: CSmith random testing.
#
# Generates random C programs with CSmith, compiles each with both clang
# (reference) and occ, runs them, and compares the printed checksum.
#
# Any divergence indicates a miscompilation bug in occ.
#
# Usage:
#   bundle exec rspec spec/phase12/           # 100 programs (default)
#   CSMITH_COUNT=1000 bundle exec rspec spec/phase12/
#   CSMITH_SEED=12345 bundle exec rspec spec/phase12/  # run one specific seed

OCC_BIN       = File.expand_path('../../bin/occ', __dir__)
CSMITH_BIN    = ENV.fetch('CSMITH_BIN', 'csmith')
CSMITH_INCLUDE = ENV.fetch('CSMITH_PATH',
  '/opt/homebrew/Cellar/csmith/2.3.0/include/csmith-2.3.0')
CSMITH_COUNT  = (ENV['CSMITH_COUNT'] || '100').to_i
CSMITH_SEED   = ENV['CSMITH_SEED']&.to_i  # nil = random seeds
CSMITH_SEED_START = (ENV['CSMITH_SEED_START'] || '1').to_i  # first seed in batch mode

SDK_INCLUDE = begin
  path = `xcrun --show-sdk-path 2>/dev/null`.strip
  path.empty? ? nil : File.join(path, 'usr', 'include')
end

RUN_TIMEOUT = 10  # seconds per program

# CSmith flags: no features occ doesn't support yet.
# --no-argc keeps main() signature clean.
CSMITH_FLAGS = %w[
  --concise
  --quiet
  --no-argc
].freeze

def run_with_timeout(cmd, timeout: RUN_TIMEOUT)
  stdout_r, stdout_w = IO.pipe
  stderr_r, stderr_w = IO.pipe

  pid = spawn(*cmd, out: stdout_w, err: stderr_w)
  stdout_w.close
  stderr_w.close

  timed_out = false
  deadline = Time.now + timeout

  loop do
    result = Process.waitpid(pid, Process::WNOHANG)
    break if result
    if Time.now > deadline
      Process.kill('KILL', pid) rescue nil
      Process.waitpid(pid) rescue nil
      timed_out = true
      break
    end
    sleep 0.05
  end

  stdout = stdout_r.read
  stderr = stderr_r.read
  stdout_r.close
  stderr_r.close

  if timed_out
    { stdout: '', stderr: 'TIMEOUT', status: -1, timeout: true }
  else
    status = $?.exitstatus
    { stdout: stdout.to_s, stderr: stderr.to_s, status: status, timeout: false }
  end
rescue StandardError => e
  { stdout: '', stderr: e.message, status: -1, timeout: false }
end

def compile_with_clang(src, out)
  cmd = ['clang', '-w', "-I#{CSMITH_INCLUDE}", src, '-o', out]
  stdout, stderr, status = Open3.capture3(*cmd)
  { stdout: stdout, stderr: stderr, status: status.exitstatus }
end

def compile_with_occ(src, out)
  args = ['ruby', OCC_BIN]
  args += ['-I', CSMITH_INCLUDE]
  args += ['-I', SDK_INCLUDE] if SDK_INCLUDE
  args += [src, '-o', out]
  stdout, stderr, status = Open3.capture3(*args)
  { stdout: stdout, stderr: stderr, status: status.exitstatus }
end

def extract_checksum(output)
  m = output.match(/checksum\s*=\s*([0-9A-Fa-f]+)/i)
  m ? m[1].upcase : nil
end

RSpec.describe 'Phase 12: CSmith random testing' do
  before(:all) do
    skip 'csmith not found' unless system("which #{CSMITH_BIN} > /dev/null 2>&1")
    skip "CSmith include dir not found: #{CSMITH_INCLUDE}" unless File.directory?(CSMITH_INCLUDE)
  end

  if CSMITH_SEED
    # Single-seed mode for reproducing a specific failure.
    it "seed #{CSMITH_SEED} produces matching output" do
      Dir.mktmpdir('csmith_') do |dir|
        src = File.join(dir, 'test.c')
        ref_bin = File.join(dir, 'test_clang')
        occ_bin = File.join(dir, 'test_occ')

        system(CSMITH_BIN, '--seed', CSMITH_SEED.to_s, *CSMITH_FLAGS, '--output', src)

        ref_compile = compile_with_clang(src, ref_bin)
        occ_compile = compile_with_occ(src, occ_bin)

        if occ_compile[:status] != 0
          fail "occ failed to compile seed #{CSMITH_SEED}:\n#{occ_compile[:stderr]}"
        end

        ref_result = run_with_timeout([ref_bin])
        occ_result = run_with_timeout([occ_bin])

        ref_cs = extract_checksum(ref_result[:stdout])
        occ_cs = extract_checksum(occ_result[:stdout])

        expect(occ_cs).to eq(ref_cs),
          "Checksum mismatch for seed #{CSMITH_SEED}: occ=#{occ_cs} ref=#{ref_cs}\n" \
          "OCC stdout: #{occ_result[:stdout]}\nRef stdout: #{ref_result[:stdout]}"
      end
    end
  else
    # Batch mode: run CSMITH_COUNT random programs.
    failures = []

    it "compiles and produces correct output for #{CSMITH_COUNT} random programs" do
      Dir.mktmpdir('csmith_batch_') do |dir|
        compiler_crash_count = 0
        checksum_mismatch_count = 0
        skip_count = 0
        pass_count = 0

        CSMITH_COUNT.times do |i|
          seed = CSMITH_SEED_START + i  # use sequential seeds for reproducibility
          src = File.join(dir, "test_#{seed}.c")
          ref_bin = File.join(dir, "ref_#{seed}")
          occ_bin_path = File.join(dir, "occ_#{seed}")

          # Generate with explicit seed for determinism
          _, _, status = Open3.capture3(CSMITH_BIN, *CSMITH_FLAGS, '--seed', seed.to_s, '--output', src)
          next unless status.success? && File.exist?(src)

          # Compile reference
          ref_compile = compile_with_clang(src, ref_bin)
          unless ref_compile[:status] == 0
            skip_count += 1
            next  # skip programs clang won't compile
          end

          # Compile with occ
          occ_compile = compile_with_occ(src, occ_bin_path)
          if occ_compile[:status] != 0
            compiler_crash_count += 1
            failures << { seed: seed, kind: :compiler_crash, msg: occ_compile[:stderr].lines.last(5).join }
            next
          end

          # Run both with timeout
          ref_result = run_with_timeout([ref_bin])
          occ_result = run_with_timeout([occ_bin_path])

          next if ref_result[:timeout]  # skip if reference times out

          if occ_result[:timeout]
            skip_count += 1
            next
          end

          ref_cs = extract_checksum(ref_result[:stdout])
          occ_cs = extract_checksum(occ_result[:stdout])

          if ref_cs && occ_cs && ref_cs != occ_cs
            checksum_mismatch_count += 1
            failures << { seed: seed, kind: :mismatch, ref: ref_cs, occ: occ_cs }
          elsif occ_cs.nil? && ref_cs
            checksum_mismatch_count += 1
            failures << { seed: seed, kind: :no_output, ref: ref_cs, stderr: occ_result[:stderr] }
          else
            pass_count += 1
          end

          # Clean up compiled binaries to save disk space
          File.delete(ref_bin) rescue nil
          File.delete(occ_bin_path) rescue nil
        end

        total = pass_count + compiler_crash_count + checksum_mismatch_count
        summary = "#{pass_count}/#{total} passed, #{compiler_crash_count} compiler crashes, " \
                  "#{checksum_mismatch_count} mismatches, #{skip_count} skipped"

        if failures.any?
          failure_details = failures.first(10).map do |f|
            case f[:kind]
            when :compiler_crash
              "  seed #{f[:seed]}: COMPILER CRASH\n    #{f[:msg].strip}"
            when :mismatch
              "  seed #{f[:seed]}: ref=#{f[:ref]} occ=#{f[:occ]}"
            when :no_output
              "  seed #{f[:seed]}: no checksum output (ref=#{f[:ref]})\n    #{f[:stderr].lines.last(3).join.strip}"
            end
          end.join("\n")

          fail "#{summary}\nFirst failures:\n#{failure_details}"
        end

        puts "\n  CSmith: #{summary}"
        expect(checksum_mismatch_count + compiler_crash_count).to eq(0)
      end
    end
  end
end
