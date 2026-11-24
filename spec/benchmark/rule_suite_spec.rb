# frozen_string_literal: true

require_relative '../../benchmark/study/rule_suite'
require 'yaml'

RSpec.describe PerformanceStudy::RuleSuite do
  it 'validates fresh graph, single, identical and twenty varied policies without timing gates' do
    %w[graph one identical varied].zip([0, 1, 20, 20]).each do |workload, count|
      result = described_class.run(pairs: 4, workload:)
      expect(result[:rule_count]).to eq(count)
      expect(result[:warm_rules].length).to eq(count)
      expect(result[:cold_graph][:allocated_objects]).to be_positive
      expect(result[:cold_plus_suite][:seconds]).to be_positive
      expect(result[:retained_suite][:ruby_heap_bytes]).to be_positive
      expect(result[:graph_sha256]).to match(/\A[0-9a-f]{64}\z/)
      expect(result[:controls]).to eq(forbidden: 4, empty: 1)
    end
  end

  it 'rejects unknown workloads rather than recording an empty successful suite' do
    expect { described_class.run(pairs: 4, workload: 'missing') }.to raise_error(ArgumentError)
  end

  it 'rejects incorrect fast results and retains allocation/time samples only after validation' do
    fake = double(check: [ArchUnit::EmptyTestViolation.new(filters: [])])
    expect { PerformanceStudy::RuleSamples.check(fake, nil) }
      .to raise_error('passing suite produced violations')
    summary = PerformanceStudy::Measurements.summarize([1, 3, 2])
    expect(summary[:median_seconds]).to eq(2)
  end

  it 'keeps paired CI manual, pinned, read-only and isolated from the discovery improvement' do
    path = File.expand_path('../../.github/workflows/performance-study.yml', __dir__)
    workflow = YAML.safe_load_file(path, aliases: true)
    job = workflow.fetch('jobs').fetch('rule-suite')
    expect(job['if']).to eq("github.event_name == 'workflow_dispatch'")
    expect(job['timeout-minutes']).to eq(25)
    expect(workflow['permissions']).to eq('contents' => 'read')
    expect(job['steps'].filter_map { |step| step['uses'] }).to all(match(/@[a-f0-9]{40}\z/))
    checkout = job['steps'].find { |step| step.dig('with', 'path') == 'baseline' }
    expect(checkout.dig('with', 'ref')).to eq('e2d347e14e0f8d06489582bcb7c5473295a7df4b')
    expect(checkout.dig('with', 'persist-credentials')).to be(false)
    commands = job['steps'].filter_map { |step| step['run'] }.join("\n")
    expect(commands).to include('1..3', 'STUDY_PAIRS', 'graph_sha256', 'rule_suite.rb')
    expect(commands).not_to include('gem push', 'bundle update')
  end
end
