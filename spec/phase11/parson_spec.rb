# frozen_string_literal: true

require 'open3'
require 'fileutils'

RSpec.describe 'Phase 11: parson — JSON library (Tier 1)', :thirdparty do
  PARSON_URL    = 'https://github.com/kgabis/parson'
  PARSON_COMMIT = 'ba29f4eda9ea7703a9f6a9cf2b0532a2605723c3'

  before(:all) { require_network! }

  it 'compiles parson and passes its tests', :slow do
    repo = git_clone(PARSON_URL, PARSON_COMMIT, 'parson')
    in_build_copy(repo, 'parson') do |dir|
      test_src = Dir["#{dir}/tests*.c"].first || File.join(dir, 'tests.c')
      parson_c = File.join(dir, 'parson.c')

      result = occ_compile(parson_c, test_src, output: './parson_tests',
                                                flags: ["-I#{dir}", '-DTESTS_MAIN'])
      expect_compiled(result)
      expect_ran_ok shell('./parson_tests')
    end
  end
end
