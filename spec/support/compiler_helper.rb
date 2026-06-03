# frozen_string_literal: true

module CompilerHelper
  OCC_BIN = File.join(__dir__, '..', '..', 'bin', 'occ')

  def run_occ(*args)
    cmd = ['ruby', OCC_BIN] + args
    stdout, stderr, status = Open3.capture3(*cmd)
    { stdout: stdout, stderr: stderr, status: status.exitstatus }
  end

  def with_c_file(content, filename: 'test.c')
    Dir.mktmpdir do |dir|
      path = File.join(dir, filename)
      File.write(path, content)
      yield path, dir
    end
  end
end

RSpec.configure do |config|
  config.include CompilerHelper
end
