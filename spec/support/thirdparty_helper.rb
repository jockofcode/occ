# frozen_string_literal: true

require 'open3'
require 'tmpdir'
require 'fileutils'

module ThirdpartyHelper
  # Clones are cached here across runs to avoid repeated network access.
  CACHE_DIR = File.expand_path('../../tmp/thirdparty_cache', __dir__)

  OCC_CC = File.expand_path('../../bin/occ_cc', __dir__)
  OCC_BIN = File.expand_path('../../bin/occ', __dir__)

  # SDK include path for macOS system headers.
  SDK_INCLUDE = begin
    path = `xcrun --show-sdk-path 2>/dev/null`.strip
    path.empty? ? nil : File.join(path, 'usr', 'include')
  end

  # ── Prerequisites ───────────────────────────────────────────────────────────

  def require_git!
    skip 'git not available' unless system('which git > /dev/null 2>&1')
  end

  def require_make!
    skip 'make not available' unless system('which make > /dev/null 2>&1')
  end

  def require_clang!
    skip 'clang not available' unless system('which clang > /dev/null 2>&1')
  end

  def require_network!
    require_git!
    require_clang!
  end

  # ── Repository management ───────────────────────────────────────────────────

  # Clone (or update) a git repo and check out a pinned commit.
  # Returns the path to the repo directory.
  def git_clone(url, commit, name)
    repo_dir = File.join(CACHE_DIR, name)
    FileUtils.mkdir_p(CACHE_DIR)

    unless File.directory?(File.join(repo_dir, '.git'))
      out, err, status = Open3.capture3('git', 'clone', '--quiet', '--no-tags', url, repo_dir)
      unless status.success?
        skip "failed to clone #{url}: #{err.strip}"
      end
    end

    unless system('git', '-C', repo_dir, 'checkout', '--quiet', commit)
      # Tag refs are not fetched with --no-tags; try fetching it explicitly first
      system('git', '-C', repo_dir, 'fetch', '--quiet', 'origin',
             "refs/tags/#{commit}:refs/tags/#{commit}")
      unless system('git', '-C', repo_dir, 'checkout', '--quiet', commit)
        # Cached repo may be corrupted — wipe and re-clone
        FileUtils.rm_rf(repo_dir)
        out, err, status = Open3.capture3('git', 'clone', '--quiet', '--no-tags', url, repo_dir)
        unless status.success?
          skip "failed to re-clone #{url}: #{err.strip}"
        end
        system('git', '-C', repo_dir, 'fetch', '--quiet', 'origin',
               "refs/tags/#{commit}:refs/tags/#{commit}")
        skip "failed to checkout #{commit}" unless system('git', '-C', repo_dir, 'checkout', '--quiet', commit)
      end
    end

    repo_dir
  end

  # Create a disposable copy of source_dir to build in, yield the path, then
  # clean up — so the cached clone is never modified by a build.
  def in_build_copy(source_dir, name)
    build_dir = Dir.mktmpdir("occ_tp_#{name}_")
    FileUtils.cp_r(Dir["#{source_dir}/*"], build_dir)
    Dir.chdir(build_dir) { yield build_dir }
  ensure
    FileUtils.rm_rf(build_dir) if build_dir
  end

  # ── Compilation helpers ─────────────────────────────────────────────────────

  # Run occ directly on one or more source files.
  # Returns { stdout:, stderr:, status: }.
  def occ_compile(*sources, output:, flags: [], include_sdk: true)
    args = ['ruby', OCC_BIN]
    args += ['-I', SDK_INCLUDE] if include_sdk && SDK_INCLUDE
    args += flags
    args += sources
    args += ['-o', output]
    stdout, stderr, status = Open3.capture3(*args)
    { stdout: stdout, stderr: stderr, status: status.exitstatus }
  end

  # Run occ_cc (the gcc-compatible wrapper) on source files.
  def occ_cc_compile(*sources, output:, flags: [], include_sdk: true)
    args = ['ruby', OCC_CC]
    args += ['-I', SDK_INCLUDE] if include_sdk && SDK_INCLUDE
    args += flags
    args += sources
    args += ['-o', output]
    stdout, stderr, status = Open3.capture3(*args)
    { stdout: stdout, stderr: stderr, status: status.exitstatus }
  end

  # Run an arbitrary command and return { stdout:, stderr:, status: }.
  def shell(*cmd, env: {})
    stdout, stderr, status = Open3.capture3(env, *cmd)
    { stdout: stdout, stderr: stderr, status: status.exitstatus }
  end

  # Run a make target in the current directory with CC set to occ_cc.
  def make_with_occ(*targets, extra_env: {})
    env = { 'CC' => "ruby #{OCC_CC}" }.merge(extra_env)
    cmd = ['make', *targets]
    shell(*cmd, env: env)
  end

  # ── Assertions ──────────────────────────────────────────────────────────────

  def expect_compiled(result)
    expect(result[:status]).to eq(0),
      "occ failed to compile:\nSTDERR: #{result[:stderr]}\nSTDOUT: #{result[:stdout]}"
  end

  def expect_ran_ok(result)
    expect(result[:status]).to eq(0),
      "program exited #{result[:status]}:\nSTDOUT: #{result[:stdout]}\nSTDERR: #{result[:stderr]}"
  end
end

RSpec.configure do |config|
  config.include ThirdpartyHelper, :thirdparty
end
