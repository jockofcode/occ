# frozen_string_literal: true

require 'open3'
require 'fileutils'

RSpec.describe 'Phase 11: zlib 1.3.2 (Tier 3)', :thirdparty do
  ZLIB_URL    = 'https://github.com/madler/zlib'
  ZLIB_COMMIT = 'e3dc0a85b7032e98380dec011bc8f2c2ee0d8fca'

  before(:all) { require_network! }

  it 'builds zlib and passes its tests', :slow do
    repo = git_clone(ZLIB_URL, ZLIB_COMMIT, 'zlib')
    in_build_copy(repo, 'zlib') do |dir|
      srcs = %w[
        adler32.c crc32.c deflate.c inflate.c inftrees.c inffast.c
        trees.c zutil.c compress.c uncompr.c
        gzlib.c gzread.c gzwrite.c gzclose.c
      ].map { |f| File.join(dir, f) }
      srcs << File.join(dir, 'test', 'example.c')

      result = occ_compile(*srcs, output: './zlib_example', flags: ["-I#{dir}"])
      expect_compiled(result)

      run = shell('./zlib_example')
      expect(run[:stdout]).to include('large_inflate(): OK')
      expect_ran_ok(run)
    end
  end
end
