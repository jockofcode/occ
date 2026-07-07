# frozen_string_literal: true

require 'rspec/core/rake_task'
require 'parallel_tests/tasks'

11.times do |i|
  n = i + 1
  RSpec::Core::RakeTask.new(:"spec:phase#{n}") do |t|
    t.pattern = "spec/phase#{n}/**/*_spec.rb"
    t.rspec_opts = '--format documentation'
    # Phase 11 is slow (network clones) and pending by default.
    # Run with: THIRDPARTY=1 rake spec:phase11
    t.rspec_opts += ' --tag ~slow' if n == 11 && ENV['THIRDPARTY'] != '1'
  end
end

# Phase 12: CSmith random testing
# Run with: rake spec:phase12
# Options: CSMITH_COUNT=1000 CSMITH_SEED=<n> CSMITH_PATH=<include_dir>
RSpec::Core::RakeTask.new(:'spec:phase12') do |t|
  t.pattern = 'spec/phase12/**/*_spec.rb'
  t.rspec_opts = '--format documentation'
end

RSpec::Core::RakeTask.new(:'spec:csmith') do |t|
  t.pattern = 'spec/phase12/**/*_spec.rb'
  t.rspec_opts = '--format documentation'
end

# Default suite: phases 1-10 only (no network, no slow tests)
RSpec::Core::RakeTask.new(:spec) do |t|
  t.pattern = 'spec/phase{1,2,3,4,5,6,7,8,9,10}/**/*_spec.rb'
  t.rspec_opts = '--format documentation'
end

# Third-party suite: network required, slow, all pending until Phase 9+
RSpec::Core::RakeTask.new(:'spec:thirdparty') do |t|
  t.pattern = 'spec/phase11/**/*_spec.rb'
  t.rspec_opts = '--format documentation'
end

task default: :spec

# Parallel test suite: phases 1-10, N processes (default: CPU count)
# Run with: rake spec:parallel
# Override count: PARALLEL_TESTS_PROCESSORS=4 rake spec:parallel
desc 'Run phases 1-10 specs in parallel'
task :'spec:parallel' do
  pattern = 'spec/phase{1,2,3,4,5,6,7,8,9,10}/**/*_spec.rb'
  exec "bundle exec parallel_rspec #{pattern}"
end

desc 'Run phase 11 third-party specs in parallel (network required)'
task :'spec:thirdparty:parallel' do
  exec 'bundle exec parallel_rspec spec/phase11/**/*_spec.rb'
end
