# frozen_string_literal: true

require 'open3'
require 'fileutils'

RSpec.describe 'Phase 11: munit — unit testing micro-framework (Tier 1)', :thirdparty do
  MUNIT_URL    = 'https://github.com/nemequ/munit'
  MUNIT_COMMIT = 'fbbdf1467eb0d04a6ee465def2e529e4c87f2118'

  before(:all) { require_network! }

  it 'compiles munit and the example suite and runs without failures', :slow do
    repo = git_clone(MUNIT_URL, MUNIT_COMMIT, 'munit')
    in_build_copy(repo, 'munit') do |dir|
      munit_c   = File.join(dir, 'munit.c')
      example_c = File.join(dir, 'example.c')
      skip 'unexpected project layout' unless File.exist?(munit_c) && File.exist?(example_c)

      result = occ_compile(munit_c, example_c, output: './munit_example', flags: ["-I#{dir}"])
      expect_compiled(result)
      expect_ran_ok shell('./munit_example')
    end
  end
end
