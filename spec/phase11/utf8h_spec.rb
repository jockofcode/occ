# frozen_string_literal: true

require 'open3'
require 'fileutils'

RSpec.describe 'Phase 11: utf8.h — header-only UTF-8 library (Tier 2)', :thirdparty do
  UTF8H_URL    = 'https://github.com/sheredom/utf8.h'
  UTF8H_COMMIT = '1194293f5b56dbb418d3b7e65410443304c40433'

  before(:all) { require_network! }

  it 'compiles utf8.h tests and runs them', :slow do
    repo = git_clone(UTF8H_URL, UTF8H_COMMIT, 'utf8h')
    in_build_copy(repo, 'utf8h') do |dir|
      test_h = File.join(dir, 'test', 'utest.h')
      utf8_h = File.join(dir, 'utf8.h')
      [test_h, utf8_h].each do |f|
        next unless File.exist?(f)
        content = File.read(f)
        content.gsub!(
          /#elif defined\(__clang__\) \|\| defined\(__GNUC__\) \|\| defined\(__TINYC__\)/,
          '#elif 1'
        )
        content.gsub!(
          /#elif defined\(__clang__\) \|\| defined\(__GNUC__\)/,
          '#elif 1'
        )
        # occ maps __typeof__ to int; force the simple #else branch to avoid type mismatches
        content.gsub!(
          '#elif defined(__GNUC__) || defined(__TINYC__)',
          '#elif 0'
        )
        # macOS clock_gettime_nsec_np is not in our minimal time.h; return 0 for timing
        content.gsub!(
          'clock_gettime_nsec_np(CLOCK_UPTIME_RAW)',
          '(utest_int64_t)0'
        )
        File.write(f, content)
      end

      test_c = File.join(dir, 'test', 'main.c')

      result = occ_compile(test_c, output: './utf8_test', flags: ["-I#{dir}"])
      expect_compiled(result)
      expect_ran_ok shell('./utf8_test')
    end
  end
end
