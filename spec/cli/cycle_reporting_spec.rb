# frozen_string_literal: true

require 'archunit/cli'
require 'json'
require 'pathname'
require 'stringio'
require 'tmpdir'

RSpec.describe ArchUnit::CLI, 'bounded cycle reporting' do
  around do |example|
    Dir.mktmpdir('archunit-cycle-reporting') do |dir|
      @root = Pathname.new(dir)
      @root.join('Gemfile').write("raise 'do not execute target'")
      @root.join('a.rb').write("require_relative 'b'\nrequire_relative 'c'")
      @root.join('b.rb').write("require_relative 'c'\nrequire_relative 'a'")
      @root.join('c.rb').write("require_relative 'a'")
      @config = @root.join('.archunit.rb')
      @config.write("rule('cycles') { project_files.should.have_no_cycles }")
      @debt = @root.join('debt.json')
      example.run
    ensure
      ArchUnit.clear_graph_cache
    end
  end

  def invoke(*arguments, command: 'check', format: 'json')
    out = StringIO.new
    err = StringIO.new
    args = [command, '--format', format, *arguments]
    code = described_class.run(args, cwd: @root.to_s, out:, err:)
    [code, format == 'json' ? JSON.parse(out.string) : out.string]
  end

  let(:flag) { %w[--cycle-reporting witness] }

  it 'keeps the default payload and order identical to explicit exhaustive mode' do
    legacy = invoke
    expect(legacy).to eq(invoke('--cycle-reporting', 'exhaustive'))
    expect(legacy.first).to eq(1)
    expect(legacy.last.dig('summary', 'violation_count')).to eq(3)
    expect(legacy.last).not_to have_key('cycle_reporting')
    expect(invoke('--output', @debt.to_s, command: 'baseline').first).to eq(0)
    bytes = @debt.binread
    accepted = invoke('--baseline', @debt.to_s, '--cycle-reporting', 'exhaustive')
    expect(accepted.last.dig('baseline', 'accepted_count')).to eq(3)
    expect(@debt.binread).to eq(bytes)
  end

  it 'labels samples as witnesses in text and additive JSON without changing the failed exit' do
    code, json = invoke(*flag)
    expect(code).to eq(1)
    expect(json).to include('cycle_reporting' => 'witness', 'schema_version' => 1)
    expect(json.dig('summary', 'violation_count')).to eq(1)
    expect(json.dig('rules', 0, 'violations', 0)).to include(
      'cycle_reporting' => 'witness', 'type' => ArchUnit::CycleViolation.name
    )
    expect(invoke(*flag, format: 'text').last).to include('Cycle witness (not exhaustive)')
    @root.join('a.rb').write('# fixed')
    code, json = invoke(*flag)
    expect(code).to eq(0)
    expect(json.dig('summary', 'violation_count')).to eq(0)
  end

  it 'fails before reading config, accepting debt, or touching baseline output' do
    @config.write("raise 'config must not be loaded'")
    @debt.write('unchanged')
    [
      invoke(*flag, '--baseline', @debt.to_s),
      invoke(*flag, '--output', @debt.to_s, '--force', command: 'baseline')
    ].each do |code, json|
      expect(code).to eq(2)
      expect(json.dig('error', 'message')).to include('incompatible with baselines')
    end
    expect(@debt.read).to eq('unchanged')
  end

  it 'also refuses a witness returned by a custom Checkable with local options' do
    expect(invoke('--output', @debt.to_s, command: 'baseline').first).to eq(0)
    bytes = @debt.binread
    @config.write(<<~RUBY)
      rule('cycles') do
        delegate = project_files.should.have_no_cycles
        Class.new do
          include ArchUnit::Checkable
          define_method(:perform_check) do |_options|
            delegate.check(ArchUnit::CheckOptions.new(cycle_reporting: :witness))
          end
        end.new
      end
    RUBY
    calls = [invoke('--baseline', @debt.to_s),
             invoke('--output', @debt.to_s, '--force', command: 'baseline')]
    calls.each do |code, json|
      expect(code).to eq(2)
      expect(json.dig('error', 'message')).to include('incompatible with baselines')
    end
    expect(@debt.binread).to eq(bytes)
  end

  it 'rejects unsupported modes and witness options on non-check commands' do
    expect(invoke('--cycle-reporting', '0').first).to eq(2)
    expect(invoke(*flag, command: 'explain').first).to eq(2)
    expect { ArchUnit::CheckOptions.new(cycle_reporting: 'witness') }
      .to raise_error(ArgumentError, /cycle_reporting/)
  end
end
