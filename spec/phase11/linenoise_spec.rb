# frozen_string_literal: true

require 'open3'
require 'fileutils'

RSpec.describe 'Phase 11: linenoise — readline replacement (Tier 3)', :thirdparty do
  LINENOISE_URL    = 'https://github.com/antirez/linenoise'
  LINENOISE_COMMIT = 'a473823d74b93eab2ba83480df16ed37617493f2'

  before(:all) { require_network! }

  it 'compiles and runs linenoise tests', :slow do
    repo = git_clone(LINENOISE_URL, LINENOISE_COMMIT, 'linenoise')
    in_build_copy(repo, 'linenoise') do |dir|
      reference_example = shell(
        'clang',
        File.join(dir, 'linenoise.c'),
        File.join(dir, 'example.c'),
        '-I', dir,
        '-o', './linenoise-example'
      )
      skip "clang failed to compile linenoise example: #{reference_example[:stderr].lines.first&.strip}" unless reference_example[:status].zero?

      reference_test = shell(
        'clang',
        File.join(dir, 'linenoise.c'),
        File.join(dir, 'linenoise-test.c'),
        '-I', dir,
        '-o', './linenoise_test'
      )
      skip "clang failed to compile linenoise tests: #{reference_test[:stderr].lines.first&.strip}" unless reference_test[:status].zero?

      reference_run = shell('./linenoise_test')
      if reference_run[:stdout].match?(/Tests failed:\s*[1-9]/) || reference_run[:status] != 0
        skip 'linenoise VT100 harness fails with clang on this host'
      end

      example_result = occ_compile(
        File.join(dir, 'linenoise.c'),
        File.join(dir, 'example.c'),
        output: './linenoise-example',
        flags: ["-I#{dir}"]
      )
      expect_compiled(example_result)

      test_result = occ_compile(
        File.join(dir, 'linenoise.c'),
        File.join(dir, 'linenoise-test.c'),
        output: './linenoise_test',
        flags: ["-I#{dir}"]
      )
      expect_compiled(test_result)

      run = shell('./linenoise_test')
      expect(run[:stdout]).to include('Tests passed:')
      expect(run[:stdout]).not_to match(/Tests failed:\s*[1-9]/)
      expect_ran_ok(run)
    end
  end
end
