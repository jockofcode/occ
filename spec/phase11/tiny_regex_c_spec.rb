# frozen_string_literal: true

require 'open3'
require 'fileutils'

RSpec.describe 'Phase 11: tiny-regex-c — regex engine (Tier 1)', :thirdparty do
  TINYREGEXC_URL    = 'https://github.com/kokke/tiny-regex-c'
  TINYREGEXC_COMMIT = 'f2632c6d9ed25272987471cdb8b70395c2460bdb'

  before(:all) { require_network! }

  it 'compiles the regex library and passes its tests', :slow do
    repo = git_clone(TINYREGEXC_URL, TINYREGEXC_COMMIT, 'tinyregexc')
    in_build_copy(repo, 'tinyregexc') do |dir|
      re_src   = File.join(dir, 're.c')
      test_src = File.join(dir, 'tests', 'test1.c')
      skip 'unexpected project layout' unless File.exist?(re_src) && File.exist?(test_src)

      result = occ_compile(re_src, test_src, output: './retest', flags: ["-I#{dir}"])
      expect_compiled(result)
      expect_ran_ok shell('./retest')
    end
  end
end
