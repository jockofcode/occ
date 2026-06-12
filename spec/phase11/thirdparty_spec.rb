# frozen_string_literal: true

require 'open3'
require 'fileutils'

# Phase 11: Third-party compilation tests.
#
# Each test clones a real-world C library or tool at a pinned commit (the same
# commit used by slimcc's linux_thirdparty.bash), compiles it with occ, and
# runs its own test suite.
#
# Tests are organised in three tiers:
#
#   Tier 1 — Achievable now (or very close): single/dual-file projects,
#             minimal dependencies, no complex language features.
#
#   Tier 2 — Needs Phase 9 language additions: va_list, designated
#             initialisers, bitfields, _Static_assert, etc.
#
#   Tier 3 — Needs Phase 9+10: full headers, complex builds, POSIX APIs.
#
# A test marked `pending` documents exactly what occ feature is missing.
# Remove the `pending` line once that feature lands.
#
# Clones are cached in tmp/thirdparty_cache/ (gitignored) to avoid
# repeated network access.

RSpec.describe 'Phase 11: Third-party compilation', :thirdparty do
  before(:all) do
    require_network!
    require_make!
  end

  # ── Tier 1 ────────────────────────────────────────────────────────────────
  # Small, self-contained projects that occ should be able to handle once
  # system header support is solid.

  describe 'jsmn — JSON tokenizer (Tier 1)', :slow do
    # ~300 lines of C, single-header library.
    # Compile: cc jsmn_test.c -o jsmn_test && ./jsmn_test
    # Requires: stdio.h, string.h, stdlib.h
    # Source: https://github.com/zserge/jsmn

    JSMN_URL    = 'https://github.com/zserge/jsmn'
    JSMN_COMMIT = '25647e692c7906b96ffd2b05ca54c097948e879c'

    it 'compiles jsmn_test.c and passes all tests' do
      repo = git_clone(JSMN_URL, JSMN_COMMIT, 'jsmn')
      in_build_copy(repo, 'jsmn') do |dir|
        # The test file is at test/tests.c; it includes jsmn.h from the root.
        test_src = File.join(dir, 'test', 'tests.c')

        result = occ_compile(test_src, output: './jsmn_test',
                                       flags: ["-I#{dir}"])
        expect_compiled(result)
        expect_ran_ok shell('./jsmn_test')
      end
    end
  end

  describe 'tinyexpr — math expression evaluator (Tier 1)', :slow do
    # Two C files: tinyexpr.c + test.c (~600 lines total).
    # Requires: stdio.h, stdlib.h, string.h, math.h, ctype.h
    # Source: https://github.com/codeplea/tinyexpr

    TINYEXPR_URL    = 'https://github.com/codeplea/tinyexpr'
    TINYEXPR_COMMIT = '4a7456e2eab88b4c76053c1c4157639ccb930e2b'

    it 'compiles tinyexpr and passes the smoke tests' do
      repo = git_clone(TINYEXPR_URL, TINYEXPR_COMMIT, 'tinyexpr')
      in_build_copy(repo, 'tinyexpr') do |dir|
        srcs = [File.join(dir, 'tinyexpr.c'), File.join(dir, 'smoke.c')]

        result = occ_compile(*srcs, output: './smoke', flags: ["-I#{dir}"])

        expect_compiled(result)
        expect_ran_ok shell('./smoke')
      end
    end
  end

  describe 'tiny-regex-c — regex engine (Tier 1)', :slow do
    # Two C files: re.c + test.c (~300 lines total).
    # Requires: stdio.h, string.h, assert.h
    # Source: https://github.com/kokke/tiny-regex-c

    TINYREGEXC_URL    = 'https://github.com/kokke/tiny-regex-c'
    TINYREGEXC_COMMIT = 'f2632c6d9ed25272987471cdb8b70395c2460bdb'

    it 'compiles the regex library and passes its tests' do
      repo = git_clone(TINYREGEXC_URL, TINYREGEXC_COMMIT, 'tinyregexc')
      in_build_copy(repo, 'tinyregexc') do |dir|
        re_src   = File.join(dir, 're.c')
        test_src = File.join(dir, 'tests', 'test1.c')
        skip 'unexpected project layout' unless File.exist?(re_src) && File.exist?(test_src)

        result = occ_compile(re_src, test_src, output: './retest',
                                                flags: ["-I#{dir}"])
        expect_compiled(result)
        expect_ran_ok shell('./retest')
      end
    end
  end

  describe 'munit — unit testing micro-framework (Tier 1)', :slow do
    # Two C files: munit.c + example.c; slimcc builds with: $CC munit.c example.c
    # Requires: stdio.h, stdlib.h, string.h, stdint.h, setjmp.h, POSIX signals
    # Source: https://github.com/nemequ/munit

    MUNIT_URL    = 'https://github.com/nemequ/munit'
    MUNIT_COMMIT = 'fbbdf1467eb0d04a6ee465def2e529e4c87f2118'

    it 'compiles munit and the example suite and runs without failures' do
      repo = git_clone(MUNIT_URL, MUNIT_COMMIT, 'munit')
      in_build_copy(repo, 'munit') do |dir|
        munit_c   = File.join(dir, 'munit.c')
        example_c = File.join(dir, 'example.c')
        skip 'unexpected project layout' unless File.exist?(munit_c) && File.exist?(example_c)

        result = occ_compile(munit_c, example_c, output: './munit_example',
                                                  flags: ["-I#{dir}"])
        expect_compiled(result)
        expect_ran_ok shell('./munit_example')
      end
    end
  end

  describe 'parson — JSON library (Tier 1)', :slow do
    # Two C files: parson.c + tests.c (~1500 lines).
    # Requires: stdio.h, stdlib.h, string.h, math.h, float.h
    # Source: https://github.com/kgabis/parson

    PARSON_URL    = 'https://github.com/kgabis/parson'
    PARSON_COMMIT = 'ba29f4eda9ea7703a9f6a9cf2b0532a2605723c3'

    it 'compiles parson and passes its tests' do
      repo = git_clone(PARSON_URL, PARSON_COMMIT, 'parson')
      in_build_copy(repo, 'parson') do |dir|
        test_src  = Dir["#{dir}/tests*.c"].first || File.join(dir, 'tests.c')
        parson_c  = File.join(dir, 'parson.c')

        result = occ_compile(parson_c, test_src, output: './parson_tests',
                                                  flags: ["-I#{dir}", '-DTESTS_MAIN'])
        expect_compiled(result)
        run = shell('./parson_tests')
        expect_ran_ok(run)
      end
    end
  end

  # ── Tier 2 ────────────────────────────────────────────────────────────────
  # Projects that need Phase 9 language features: va_list, bitfields,
  # designated initialisers, _Static_assert, __attribute__ passthrough.

  describe 'smaz — short-string compression (Tier 2)', :slow do
    # ~200 lines, single C file + test harness.
    # Requires: stdio.h, string.h, stdlib.h
    # Source: https://github.com/antirez/smaz

    SMAZ_URL    = 'https://github.com/antirez/smaz'
    SMAZ_COMMIT = '2f625846a775501fb69456567409a8b12f10ea25'

    it 'compiles smaz and passes its tests' do
      repo = git_clone(SMAZ_URL, SMAZ_COMMIT, 'smaz')
      in_build_copy(repo, 'smaz') do |dir|
        smaz_c = File.join(dir, 'smaz.c')
        test_c = File.join(dir, 'smaz_test.c')

        result = occ_compile(smaz_c, test_c, output: './smaz_test',
                                              flags: ["-I#{dir}"])
        expect_compiled(result)
        expect_ran_ok shell('./smaz_test')
      end
    end
  end

  describe 'sds — simple dynamic strings (Tier 2)', :slow do
    # ~1200 lines. Requires POSIX types, va_list for sdscatprintf.
    # Source: https://github.com/antirez/sds

    SDS_URL    = 'https://github.com/antirez/sds'
    SDS_COMMIT = '5347739b1581fcba74fd5cab1fc21d2aef321571'

    it 'compiles sds-test and passes all assertions' do
      repo = git_clone(SDS_URL, SDS_COMMIT, 'sds')
      in_build_copy(repo, 'sds') do |dir|
        sds_c = File.join(dir, 'sds.c')

        result = occ_compile(sds_c, output: './sds_test',
                                    flags: ["-I#{dir}", '-DSDS_TEST_MAIN'])
        expect_compiled(result)
        expect_ran_ok shell('./sds_test')
      end
    end
  end

  describe 'genann — minimal neural network (Tier 2)', :slow do
    # Single C file + example + tests. Uses math functions.
    # Source: https://github.com/codeplea/genann

    GENANN_URL    = 'https://github.com/codeplea/genann'
    GENANN_COMMIT = '4f72209510c9792131bd8c4b0347272b088cfa80'

    it 'compiles genann and passes its test suite' do
      pending 'requires <math.h> exp/sqrt and compound literal initialisers (Phase 9)'

      repo = git_clone(GENANN_URL, GENANN_COMMIT, 'genann')
      in_build_copy(repo, 'genann') do |dir|
        genann_c = File.join(dir, 'genann.c')
        test_c   = Dir["#{dir}/test*.c"].first

        result = occ_compile(genann_c, test_c, output: './genann_test',
                                               flags: ["-I#{dir}"])
        expect_compiled(result)
        expect_ran_ok shell('./genann_test')
      end
    end
  end

  describe 'utf8.h — header-only UTF-8 library (Tier 2)', :slow do
    # Single-header; compile test/main.c -I./
    # Requires: stdio.h, string.h, stdint.h
    # Source: https://github.com/sheredom/utf8.h

    UTF8H_URL    = 'https://github.com/sheredom/utf8.h'
    UTF8H_COMMIT = '1194293f5b56dbb418d3b7e65410443304c40433'

    it 'compiles utf8.h tests and runs them' do
      pending 'requires stdint.h fixed-width types and __attribute__ passthrough (Phase 9)'

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
          File.write(f, content)
        end

        test_c = File.join(dir, 'test', 'main.c')

        result = occ_compile(test_c, output: './utf8_test', flags: ["-I#{dir}"])

        expect_compiled(result)
        expect_ran_ok shell('./utf8_test')
      end
    end
  end

  # ── Tier 3 ────────────────────────────────────────────────────────────────
  # Larger projects that need Phase 9+10 (full headers, POSIX, complex builds).
  # Documented here as aspirational targets.

  describe 'linenoise — readline replacement (Tier 3)', :slow do
    # Source: https://github.com/antirez/linenoise (tag 2.0)
    it 'compiles and runs linenoise tests' do
      skip 'requires POSIX termios, ioctl, and full <unistd.h> support (Phase 10)'
    end
  end

  describe 'lua 5.5 (Tier 3)', :slow do
    # Source: https://lua.org/ftp/lua-5.5.0.tar.gz
    it 'builds the Lua interpreter from source' do
      skip 'requires full C standard library, va_list, longjmp, and complex macros (Phase 10)'
    end
  end

  describe 'zlib 1.3.2 (Tier 3)', :slow do
    # Source: https://github.com/madler/zlib (tag v1.3.2)
    it 'builds zlib and passes its tests' do
      skip 'requires full <stdio.h>, POSIX file I/O, and bitfield struct support (Phase 10)'
    end
  end

  describe 'sqlite (Tier 3)', :slow do
    # Source: https://github.com/sqlite/sqlite
    it 'compiles the sqlite amalgamation' do
      skip 'requires near-complete C11, complex macros, and va_list (Phase 10)'
    end
  end
end
