# frozen_string_literal: true

require 'open3'
require 'fileutils'

RSpec.describe 'Phase 11: smaz — short-string compression (Tier 2)', :thirdparty do
  SMAZ_URL    = 'https://github.com/antirez/smaz'
  SMAZ_COMMIT = '2f625846a775501fb69456567409a8b12f10ea25'

  before(:all) { require_network! }

  it 'compiles smaz and passes its tests', :slow do
    repo = git_clone(SMAZ_URL, SMAZ_COMMIT, 'smaz')
    in_build_copy(repo, 'smaz') do |dir|
      smaz_c = File.join(dir, 'smaz.c')
      test_c = File.join(dir, 'smaz_test.c')

      result = occ_compile(smaz_c, test_c, output: './smaz_test', flags: ["-I#{dir}"])
      expect_compiled(result)
      expect_ran_ok shell('./smaz_test')
    end
  end
end
