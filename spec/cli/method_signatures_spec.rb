# frozen_string_literal: true

require 'archunit/cli'
require 'json'
require 'pathname'
require 'stringio'
require 'tmpdir'

RSpec.describe ArchUnit::CLI, 'declared method signatures' do
  around do |example|
    Dir.mktmpdir('archunit-signature-cli') do |directory|
      @root = Pathname.new(directory)
      @root.join('Gemfile').write("raise 'never execute target'")
      @source = @root.join('command.rb')
      @baseline = @root.join('debt.json')
      source('def call; end')
      configure
      example.run
    ensure
      ArchUnit.clear_graph_cache
    end
  end

  def source(body)
    @source.write("module Commands; class Run; #{body}; end; end\nraise 'never boot'")
  end

  def configure(positionals: 1, selector: "in_namespace('Commands')")
    @root.join('.archunit.rb').write(<<~RUBY)
      rule('command shape') do
        shape = ArchUnit::MethodSignature.new(name: :call, positional: #{positionals}, keywords: [:actor])
        project_classes.#{selector}.should.declare_method(shape)
      end
    RUBY
  end

  def invoke(command = 'check', *flags)
    out = StringIO.new
    args = [command, '--format=json', *flags]
    status = described_class.run(args, cwd: @root.to_s, out:, err: StringIO.new)
    [status, JSON.parse(out.string)]
  end

  it 'reports source declarations and structured evidence for incompatible shapes' do
    code, report = invoke
    expect(code).to eq(1)
    expect(report.dig('analysis', 'scopes', 0, 'kind')).to eq('source_declarations')
    finding = report.dig('rules', 0, 'violations', 0, 'method_signature')
    expect(finding).to include('owner' => 'Commands::Run', 'reason' => 'incompatible_signature',
                               'unknown' => false)
    expected = { 'name' => 'call', 'positional' => 1, 'keywords' => ['actor'] }
    expect(finding['expected']).to include(expected)
    expect(finding['candidates']).to contain_exactly(
      include('parameters' => [], 'site' => include('file' => 'command.rb', 'line' => 1))
    )
    source('def call(id, actor:); end')
    expect(invoke.first).to eq(0)
  end

  it 'preserves baselines across line movement but not shape or scope changes' do
    code, report = invoke('baseline', '--output', @baseline.to_s)
    expect(code).to eq(0)
    expect(report.dig('baseline', 'accepted_count')).to eq(1)
    document = JSON.parse(@baseline.read)
    entry = document.fetch('entries').first
    expect(entry.dig('data', 'policy')).to eq('declared_shape_v1')
    expect(entry.dig('context', 0, 'kind')).to eq('source_declarations')
    @source.write("# moved\n#{@source.read}")
    expect(invoke('check', '--baseline', @baseline.to_s).first).to eq(0)
    configure(positionals: 2)
    expect(invoke('check', '--baseline', @baseline.to_s).last.fetch('baseline'))
      .to include('new_count' => 1, 'stale_count' => 1)
    configure(selector: "with_constant_name('Commands::Run')")
    expect(invoke('check', '--baseline', @baseline.to_s).first).to eq(1)
  end

  it 'never creates or applies accepted debt for a conditional or unknown result' do
    expect(invoke('baseline', '--output', @baseline.to_s).first).to eq(0)
    before = @baseline.binread
    source('def call(id, actor:); end if feature?')
    code, report = invoke
    expect(code).to eq(1)
    finding = report.dig('rules', 0, 'violations', 0, 'method_signature')
    expect(finding).to include('reason' => 'uncertain_method_declaration', 'unknown' => true)
    attempts = [
      invoke('check', '--baseline', @baseline.to_s),
      invoke('baseline', '--output', @baseline.to_s, '--force')
    ]
    attempts.each do |status, result|
      expect(status).to eq(2)
      message = result.dig('error', 'message')
      expect(message).to include('cannot baseline an unknown method signature')
    end
    expect(@baseline.binread).to eq(before)
  end

  it 'does not transfer debt between same-spelled constants in different encodings' do
    name = "\u00C9quipe"
    declaration = "class #{name}; def call; end; end"
    @source.binwrite(declaration)
    configure(selector: 'with_constant_name("\u00C9quipe")')
    expect(invoke('baseline', '--output', @baseline.to_s).first).to eq(0)

    @source.binwrite("# encoding: ISO-8859-1\n#{declaration}".encode('ISO-8859-1'))
    configure(selector: 'with_constant_name("\u00C9quipe".encode("ISO-8859-1"))')
    status, report = invoke('check', '--baseline', @baseline.to_s)
    expect(status).to eq(1)
    expect(report.fetch('baseline')).to include('new_count' => 1, 'stale_count' => 1)
    finding = report.dig('rules', 0, 'violations', 0, 'method_signature')
    identifier = { 'text' => name, 'encoding' => 'ISO-8859-1', 'bytes' => 'c97175697065' }
    expect(finding.fetch('owner')).to eq(identifier)
    expect(finding.dig('selector', 'constants')).to eq([identifier])
  end

  it 'reports no selected classes separately and does not baseline an empty guard' do
    configure(selector: "in_namespace('Elsewhere')")
    code, report = invoke
    expect(code).to eq(1)
    expect(report.dig('rules', 0, 'violations', 0, 'class_selector', 'namespaces'))
      .to eq(['Elsewhere'])
    expect(invoke('baseline', '--output', @baseline.to_s).first).to eq(2)
    expect(@baseline).not_to exist
  end
end
