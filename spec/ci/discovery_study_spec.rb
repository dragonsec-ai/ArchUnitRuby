# frozen_string_literal: true

require 'yaml'

RSpec.describe 'the source-discovery study workflow' do
  subject(:workflow) do
    YAML.safe_load_file(
      File.expand_path('../../.github/workflows/performance-study.yml', __dir__), aliases: true
    )
  end

  let(:job) { workflow.fetch('jobs').fetch('discovery') }

  it 'runs only on explicit dispatch with read-only access and a bounded platform matrix' do
    triggers = workflow.fetch('on') { workflow.fetch(true) }
    expect(triggers.keys).to include('workflow_dispatch')
    expect(job.fetch('if')).to eq("github.event_name == 'workflow_dispatch'")
    expect(job.fetch('steps')[1].dig('with', 'ref')).to eq('v1.1.0')
    expect(workflow.fetch('permissions')).to eq('contents' => 'read')
    expect(job.fetch('timeout-minutes')).to eq(20)
    expect(job.dig('strategy', 'matrix', 'os'))
      .to contain_exactly('ubuntu-latest', 'windows-latest')
  end

  it 'pins actions and disables checkout credentials for both production library revisions' do
    actions = job.fetch('steps').filter_map { |step| step['uses'] }
    expect(actions).to all(match(/@[a-f0-9]{40}\z/))
    checkouts = job.fetch('steps').select do |step|
      step.fetch('uses', '').include?('actions/checkout')
    end
    expect(checkouts.length).to eq(2)
    expect(checkouts).to all(include('with' => include('persist-credentials' => false)))
  end

  it 'reuses one benchmark harness and checks semantic digests and cache/source counts per pair' do
    run = job.fetch('steps').find { |step| step['run'] }.fetch('run')
    expect(run).to include('Copy-Item', 'benchmark/extraction.rb', '--excluded-files')
    expect(run).to include('graph_sha256', 'graph_cache_reused', 'source_files', '1..3')
    expect(run).to include('sparse-5000', 'sparse-10000', 'imports-1000', 'excluded-1000')
    expect(run).not_to include('bundle update', 'gem push', 'inputs.baseline')
    upload = job.fetch('steps').find { |step| step.fetch('uses', '').include?('upload-artifact') }
    expect(upload).to include('if' => 'always()', 'with' => include('path' => 'reports/*.json'))
  end
end
