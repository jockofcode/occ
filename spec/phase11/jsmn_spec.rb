# frozen_string_literal: true

require 'open3'
require 'fileutils'

RSpec.describe 'Phase 11: jsmn — JSON tokenizer (Tier 1)', :thirdparty do
  JSMN_URL    = 'https://github.com/zserge/jsmn'
  JSMN_COMMIT = '25647e692c7906b96ffd2b05ca54c097948e879c'

  before(:all) { require_network! }

  it 'compiles jsmn_test.c and passes all tests', :slow do
    repo = git_clone(JSMN_URL, JSMN_COMMIT, 'jsmn')
    in_build_copy(repo, 'jsmn') do |dir|
      test_src = File.join(dir, 'test', 'tests.c')

      result = occ_compile(test_src, output: './jsmn_test', flags: ["-I#{dir}"])
      expect_compiled(result)
      expect_ran_ok shell('./jsmn_test')
    end
  end
end
