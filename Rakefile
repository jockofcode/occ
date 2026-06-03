# frozen_string_literal: true

require 'rspec/core/rake_task'

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
