# frozen_string_literal: true

require 'open3'
require 'fileutils'

RSpec.describe 'Phase 11: genann — minimal neural network (Tier 2)', :thirdparty do
  GENANN_URL    = 'https://github.com/codeplea/genann'
  GENANN_COMMIT = '4f72209510c9792131bd8c4b0347272b088cfa80'

  before(:all) { require_network! }

  it 'compiles genann and passes its test suite', :slow do
    repo = git_clone(GENANN_URL, GENANN_COMMIT, 'genann')
    in_build_copy(repo, 'genann') do |dir|
      genann_c = File.join(dir, 'genann.c')
      test_c   = Dir["#{dir}/test*.c"].first

      result = occ_compile(genann_c, test_c, output: './genann_test', flags: ["-I#{dir}"])
      expect_compiled(result)
      expect_ran_ok shell('./genann_test')
    end
  end
end
