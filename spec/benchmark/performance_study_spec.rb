# frozen_string_literal: true

require 'json'
require 'tmpdir'
require 'yaml'
require_relative '../../benchmark/study/run'

RSpec.describe PerformanceStudy::Runner do
  it 'keeps the isolated path-gem lock synchronized with the candidate version' do
    lock = File.read(File.expand_path('../../benchmark/study/Gemfile.lock', __dir__))
    version = Regexp.escape(ArchUnit::VERSION)
    expect(lock).to match(/^    archunit \(#{version}\)$/)
    expect(lock).to match(/^  archunit \(#{version}\)$/)
  end

  it 'checks permitted, forbidden and changed-source policies across all shapes and densities' do
    results = described_class.run(pairs: 4, trials: 1, compare: false, startup: false)
    expect(results.length).to eq(8)
    results.each do |result|
      sample = result[:samples].fetch('archunit').first
      expected = result[:policy] == 'forbidden' ? result[:pairs] * result[:density] : 0
      changed = result[:policy] == 'forbidden' ? expected + 1 : 0
      expect(sample[:cold][:violations]).to eq(expected)
      expect(sample[:warm][:violations]).to eq(expected)
      expect(sample[:after_change][:violations]).to eq(changed)
      expect(result[:summary]['archunit'][:cold][:samples_seconds].length).to eq(1)
    end
  end

  it 'computes medians correctly for odd and even samples without a timing threshold' do
    expect(PerformanceStudy::Measurements.summarize([3.0, 1.0, 2.0])[:median_seconds]).to eq(2.0)
    expect(PerformanceStudy::Measurements.summarize([4.0, 1.0, 3.0,
                                                     2.0])[:median_seconds]).to eq(2.5)
    expect { described_class.run(trials: 0) }.to raise_error(ArgumentError)
  end

  it 'uses bounded read-only Linux CI with immutable sources, research-only deps and artifacts' do
    path = File.expand_path('../../.github/workflows/performance-study.yml', __dir__)
    workflow = YAML.safe_load_file(path, aliases: true)
    expect(workflow['permissions']).to eq('contents' => 'read')
    job = workflow.fetch('jobs').fetch('study')
    expect(job['timeout-minutes']).to eq(15)
    commands = job['steps'].filter_map { |step| step['run'] }.join("\n")
    expect(commands).to include('--archspec', 'real_project.rb', 'semantic/probes.rb')
    expect(commands).not_to include('bundle update', 'gem push')
    actions = job['steps'].filter_map { |step| step['uses'] }
    expect(actions).to all(match(/@[a-f0-9]{40}\z/))
    checkout = job['steps'].find { |step| step.dig('with', 'repository') == 'discourse/discourse' }
    expect(checkout['with']['ref']).to eq('2de9c9be4f89e392fe500dd27f928d6b1184bf09')
    expect(checkout['with']['persist-credentials']).to be(false)
  end
end
