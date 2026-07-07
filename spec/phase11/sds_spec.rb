# frozen_string_literal: true

require 'open3'
require 'fileutils'

RSpec.describe 'Phase 11: sds — simple dynamic strings (Tier 2)', :thirdparty do
  SDS_URL    = 'https://github.com/antirez/sds'
  SDS_COMMIT = '5347739b1581fcba74fd5cab1fc21d2aef317d71'

  before(:all) { require_network! }

  it 'compiles sds-test and passes all assertions', :slow do
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
