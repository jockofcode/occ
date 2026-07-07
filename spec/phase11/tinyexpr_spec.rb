# frozen_string_literal: true

require 'open3'
require 'fileutils'

RSpec.describe 'Phase 11: tinyexpr — math expression evaluator (Tier 1)', :thirdparty do
  TINYEXPR_URL    = 'https://github.com/codeplea/tinyexpr'
  TINYEXPR_COMMIT = '4a7456e2eab88b4c76053c1c4157639ccb930e2b'

  before(:all) { require_network! }

  it 'compiles tinyexpr and passes the smoke tests', :slow do
    repo = git_clone(TINYEXPR_URL, TINYEXPR_COMMIT, 'tinyexpr')
    in_build_copy(repo, 'tinyexpr') do |dir|
      srcs = [File.join(dir, 'tinyexpr.c'), File.join(dir, 'smoke.c')]

      result = occ_compile(*srcs, output: './smoke', flags: ["-I#{dir}"])
      expect_compiled(result)
      expect_ran_ok shell('./smoke')
    end
  end
end
