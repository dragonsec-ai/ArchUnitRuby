# frozen_string_literal: true

require 'archunit/cli'
require 'json'
require 'pathname'
require 'stringio'
require 'tmpdir'

RSpec.describe ArchUnit::CLI, 'named method call restrictions' do
  around do |example|
    Dir.mktmpdir('archunit-cli-calls') do |dir|
      @root = Pathname.new(dir)
      @root.join('Gemfile').write("raise 'must not boot'")
      @source = @root.join('query.rb')
      @source.write('store.delete_all')
      @debt = @root.join('debt.json')
      @root.join('.archunit.rb').write(<<~RUBY)
        rule('read only') { project_files.in_path('query.rb').should_not.contain_calls_named(:delete_all) }
        rule('second policy') { project_files.in_path('query.rb').should_not.contain_calls_named(:update_all) }
      RUBY
      example.run
    ensure
      ArchUnit.clear_graph_cache
    end
  end

  def check(command = 'check', *args)
    out = StringIO.new
    flags = [command, '--format=json', *args]
    code = described_class.run(flags, cwd: @root.to_s, out:, err: StringIO.new)
    [code, JSON.parse(out.string)]
  end

  it 'reports structured syntax evidence and reuses the source-only analysis across rules' do
    code, report = check
    expect(code).to eq(1)
    violations = report.fetch('rules').first.fetch('violations')
    expect(violations.first.fetch('call')).to eq(
      'file' => 'query.rb', 'name' => 'delete_all', 'receiver' => 'explicit',
      'line' => 1, 'column' => 7, 'safe_navigation' => false
    )
    expect(report.dig('analysis', 'scopes')).to contain_exactly(
      include('kind' => 'source_calls', 'cache_hits' => 1, 'observations' => 2)
    )
    @source.write('store.read')
    expect(check.first).to eq(0)
  end

  it 'accepts one occurrence despite shifted lines, but never hides a new occurrence' do
    expect(check('baseline', '--output', @debt.to_s).first).to eq(0)
    entry = JSON.parse(@debt.read).fetch('entries').first
    expect(entry.fetch('data')).to eq(
      'file' => 'query.rb', 'name' => 'delete_all', 'receiver' => 'explicit',
      'safe_navigation' => false
    )
    @source.write("# added comment\nstore.delete_all\n")
    expect(check('check', '--baseline', @debt.to_s).first).to eq(0)
    @source.write("store.delete_all\nstore.delete_all\n")
    code, report = check('check', '--baseline', @debt.to_s)
    expect(code).to eq(1)
    expect(report.fetch('baseline')).to include('accepted_count' => 1, 'new_count' => 1)
    @source.write('store&.delete_all')
    expect(check('check', '--baseline', @debt.to_s).last.fetch('baseline'))
      .to include('accepted_count' => 0, 'new_count' => 1, 'stale_count' => 1)
  end

  it 'does not accept a partial parse even after a previously passing check' do
    @source.write('store.read')
    expect(check.first).to eq(0)
    @source.write('class Broken <')
    code, report = check
    expect(code).to eq(2)
    expect(report.dig('error', 'diagnostics')).not_to be_empty
    expect(report.dig('analysis', 'scopes', 0)).to include(
      'kind' => 'source_calls', 'status' => 'error'
    )
  end
end
