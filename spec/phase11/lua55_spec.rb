# frozen_string_literal: true

require 'open3'
require 'fileutils'

RSpec.describe 'Phase 11: lua 5.5 (Tier 3)', :thirdparty do
  LUA55_URL    = 'https://github.com/lua/lua'
  LUA55_COMMIT = 'a5522f06d2679b8f18534fd6a9968f7eb539dc31'

  LUA55_SRCS = %w[
    lapi.c lcode.c lctype.c ldebug.c ldo.c ldump.c lfunc.c lgc.c linit.c
    llex.c lmem.c lobject.c lopcodes.c lparser.c lstate.c lstring.c ltable.c
    ltm.c lundump.c lvm.c lzio.c
    lauxlib.c lbaselib.c lcorolib.c ldblib.c liolib.c lmathlib.c loslib.c
    lstrlib.c ltablib.c lutf8lib.c loadlib.c lua.c
  ].freeze

  before(:all) { require_network! }

  it 'builds the Lua interpreter from source', :slow do
    src_dir = git_clone(LUA55_URL, LUA55_COMMIT, 'lua55')

    in_build_copy(src_dir, 'lua55') do |dir|
      sources = LUA55_SRCS.map { |f| File.join(dir, f) }
      result = occ_compile(*sources,
                           output: './lua55',
                           flags: ["-I#{dir}", '-D', 'LUA_USE_JUMPTABLE=0'])
      expect_compiled(result)

      run = shell('./lua55', '-e', 'print(1+2)')
      expect(run[:stdout].strip).to eq('3')
      expect_ran_ok(run)

      run = shell('./lua55', '-e', <<~LUA)
        local x = 10
        local f = function() return x + 5 end
        assert(f() == 15)
        print("closures ok")
      LUA
      expect(run[:stdout].strip).to eq('closures ok')
      expect_ran_ok(run)

      run = shell('./lua55', '-e', <<~LUA)
        local mt = {}
        mt.__add = function(a, b) return setmetatable({v = a.v + b.v}, mt) end
        local a = setmetatable({v=10}, mt)
        local b = setmetatable({v=32}, mt)
        local c = a + b
        assert(c.v == 42, "expected 42, got " .. tostring(c.v))
        print("metamethods ok")
      LUA
      expect(run[:stdout].strip).to eq('metamethods ok')
      expect_ran_ok(run)

      run = shell('./lua55', '-e', <<~LUA)
        local Vec = {}
        Vec.__index = Vec
        function Vec.new(x,y) return setmetatable({x=x,y=y},Vec) end
        function Vec:__add(o) return Vec.new(self.x+o.x, self.y+o.y) end
        local v = Vec.new(1,2) + Vec.new(3,4)
        assert(v.x==4 and v.y==6)
        print("oop ok")
      LUA
      expect(run[:stdout].strip).to eq('oop ok')
      expect_ran_ok(run)

      run = shell('./lua55', '-e', <<~LUA)
        assert(math.abs(-5) == 5)
        assert(string.upper("hello") == "HELLO")
        assert(table.concat({1,2,3}, ",") == "1,2,3")
        assert(#"test" == 4)
        print("stdlib ok")
      LUA
      expect(run[:stdout].strip).to eq('stdlib ok')
      expect_ran_ok(run)

      run = shell('./lua55', '-e', <<~LUA)
        local s = string.pack('<f', -1.5)
        assert(#s == 4, "wrong length: " .. #s)
        local b1,b2,b3,b4 = string.byte(s,1,4)
        assert(b1==0 and b2==0 and b3==0xc0 and b4==0xbf,
          string.format("wrong bytes: %02x %02x %02x %02x", b1, b2, b3, b4))
        local v = string.unpack('<f', s)
        assert(math.abs(v - (-1.5)) < 1e-6, "unpack mismatch: " .. v)
        print("string.pack float ok")
      LUA
      expect(run[:stdout].strip).to eq('string.pack float ok')
      expect_ran_ok(run)

      tests_dir = git_clone(LUA55_URL, LUA55_COMMIT, 'lua_tests')
      tpack_src = File.join(tests_dir, 'testes', 'tpack.lua')
      if File.exist?(tpack_src)
        FileUtils.cp(tpack_src, './tpack.lua')
        run = shell('./lua55', 'tpack.lua')
        expect(run[:stdout]).to include('OK'),
          "tpack.lua failed:\nSTDOUT: #{run[:stdout]}\nSTDERR: #{run[:stderr]}"
        expect_ran_ok(run)
      end
    end
  end
end
