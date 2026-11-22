# frozen_string_literal: true

require 'archunit/cli'
require 'fileutils'
require 'json'
require 'pathname'
require 'stringio'
require 'tmpdir'

RSpec.describe ArchUnit::CLI, 'analysis diagnostics' do
  around do |example|
    Dir.mktmpdir('archunit-diagnostics') do |base|
      @root = Pathname.new(base).join('project')
      @root.mkpath
      @config = Pathname.new(base).join('trusted.rb')
      @root.join('Gemfile').write("raise 'must not run Gemfile'")
      @root.join('app.rb').write("require plugin_path\nMissing\nDb\nraise 'must not run source'")
      @root.join('one.rb').write('module Db; end')
      @root.join('two.rb').write('module Db; end')
      @config.write(<<~RUBY)
        rule('first') { project_files.should.have_name('*.rb') }
        rule('second') { project_files.should.have_no_cycles }
      RUBY
      example.run
    ensure
      ArchUnit.clear_graph_cache
    end
  end

  def invoke(*arguments, format: 'json', command: 'check')
    out = StringIO.new
    err = StringIO.new
    status = described_class.run(
      [command, '--project', @root.to_s, '--config', @config.to_s, '--format', format, *arguments],
      out:, err:, cwd: @root.to_s
    )
    [status, format == 'json' ? JSON.parse(out.string) : out.string, err.string]
  end

  it 'adds schema-one analysis scopes without changing passing policies or violation summaries' do
    code, payload, errors = invoke('--dependency-analysis', 'imports_and_constants')
    expect(code).to eq(0)
    expect(errors).to eq('')
    expect(payload).to include('schema_version' => 1, 'status' => 'passed')
    expect(payload['summary']).to eq('rule_count' => 2, 'violation_count' => 0)
    expect(payload.dig('analysis', 'status')).to eq('available')
    expected = {
      'kind' => 'dependency_graph', 'dependency_analysis' => 'imports_and_constants',
      'observations' => 2, 'cache_hits' => 1, 'rule_names' => %w[first second],
      'counters' => { 'source_files' => 3, 'imports' => 0, 'unresolved_imports' => 1,
                      'unresolved_constant_references' => 1, 'ambiguous_constant_references' => 1 }
    }
    expect(payload.dig('analysis', 'scopes')).to contain_exactly(include(expected))
    rules = payload['rules'].map { |rule| rule['analysis'] }
    expect(rules).to all(eq('status' => 'available', 'scope_ids' => [1]))
    expect(payload['analysis']['notice']).to include('not semantic coverage', 'not proof')
  end

  it 'renders meaningful uncertainty and unavailable counts in concise text' do
    code, output, errors = invoke(format: 'text')
    expect(code).to eq(0)
    expect(errors).to eq('')
    expect(output).to include('Analysis: available', 'source_files=3', 'unresolved_imports=1',
                              'unresolved_constant_references=unavailable', 'cache_hits=1',
                              'not proof of complete runtime architecture')
  end

  it 'exposes metric scopes separately and marks custom checks without extraction unavailable' do
    @config.write(<<~RUBY)
      rule('source metrics') { metrics.count.classes.should_be_above_or_equal(0) }
      rule('custom') do
        Class.new do
          include ArchUnit::Checkable
          def perform_check(_options) = []
        end.new
      end
    RUBY
    code, payload = invoke('--dependency-analysis', 'imports_and_constants')
    expect(code).to eq(0)
    expect(payload.dig('analysis', 'status')).to eq('partial')
    scopes = payload.dig('analysis', 'scopes')
    expect(scopes.length).to eq(1)
    expect(scopes.first).to include('kind' => 'source_metrics', 'dependency_analysis' => nil)
    expect(scopes.first['counters']).to include('source_files' => 3, 'unresolved_imports' => nil)
    expect(payload['rules'].last['analysis']).to eq('status' => 'unavailable', 'scope_ids' => [])
  end

  it 'shows unavailable analysis for explanation instead of implying zero unresolved references' do
    code, payload = invoke(command: 'explain')
    expect(code).to eq(0)
    expect(payload.dig('analysis', 'status')).to eq('unavailable')
    expect(payload.dig('analysis', 'scopes')).to eq([])
    expect(payload['rules'].map do |rule|
      rule['analysis']['status']
    end).to eq(%w[unavailable unavailable])
  end

  it 'does not claim analysis for a custom-only check with no built-in extraction' do
    @config.write(<<~RUBY)
      rule('custom') do
        Class.new do
          include ArchUnit::Checkable
          def perform_check(_options) = []
        end.new
      end
    RUBY
    code, payload = invoke
    expect(code).to eq(0)
    expect(payload.dig('analysis', 'status')).to eq('unavailable')
    expect(payload.dig('analysis', 'scopes')).to eq([])
  end

  it 'keeps parse failures fatal with structured diagnostics and unavailable scope counts' do
    @root.join('broken.rb').write('class Broken <')
    code, payload = invoke
    expect(code).to eq(2)
    expect(payload.dig('error', 'type')).to eq('ArchUnit::SourceParseError')
    expect(payload.dig('error', 'diagnostics')).not_to be_empty
    scopes = payload.dig('analysis', 'scopes')
    expect(scopes.length).to eq(1)
    expect(scopes.first).to include('status' => 'error')
    expect(scopes.first['counters'].values).to all(be_nil)
    code, _out, errors = invoke(format: 'text')
    expect(code).to eq(2)
    expect(errors).to include('source_files=unavailable', 'Analysis: partial')
  end

  it 'keeps different analysis roots and source policies separate rather than double counting' do
    other = @root.dirname.join('other')
    other.mkpath
    other.join('Gemfile').write('# marker')
    other.join('only.rb').write('# source')
    @config.write(<<~RUBY)
      rule('default') { project_files.should.have_name('*.rb') }
      rule('other') { ArchUnit.project_files(#{other.to_s.dump}).should.have_name('*.rb') }
      rule('narrow') do
        base = project_files.should.have_name('*.rb')
        Class.new do
          include ArchUnit::Checkable
          define_method(:perform_check) do |options|
            base.check(options.with(source_exclusions: ['two.rb']))
          end
        end.new
      end
    RUBY
    code, payload = invoke
    expect(code).to eq(0)
    scopes = payload.dig('analysis', 'scopes')
    expect(scopes.map { |scope| scope['counters']['source_files'] }).to eq([3, 1, 2])
    expect(payload['rules'].map { |rule| rule['analysis']['scope_ids'] }).to eq([[1], [2], [3]])
    expect(payload['analysis']).not_to have_key('total_source_files')
  end
end
