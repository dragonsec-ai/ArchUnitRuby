# frozen_string_literal: true

require 'tmpdir'
require 'stringio'
require 'archunit/cli'

RSpec.describe 'Rule view reuse' do
  around do |example|
    Dir.mktmpdir('archunit-rule-views') do |root|
      @root = root
      File.write(File.join(root, 'a.rb'), "require_relative 'b'\nrequire 'json'")
      File.write(File.join(root, 'b.rb'), "require_relative 'a'")
      File.write(File.join(root, 'isolated.rb'), '# no imports')
      ArchUnit.clear_graph_cache
      example.run
    ensure
      ArchUnit.clear_graph_cache
    end
  end

  def dependency_rules
    scope = ArchUnit.files(@root).with_name('a.rb')
    [scope.should.depend_on_files.with_name('isolated.rb'),
     scope.should_not.depend_on_files.with_name('b.rb'),
     scope.should.depend_on_external_modules.matching('set'),
     scope.should_not.depend_on_external_modules.matching('json')]
  end

  def other_rules
    [ArchUnit.files(@root).should.have_no_cycles,
     ArchUnit.files(@root).with_name('isolated.rb').should.have_name('wrong.rb'),
     ArchUnit.files(@root).with_name('absent.rb').should_not.have_name('*.rb'), layer_rule]
  end

  def layer_rule
    ArchUnit.layers(@root).layer('A').defined_by('a.rb').layer('B').defined_by('b.rb')
            .where_layer('A').may_not_depend_on_layers('B')
  end

  it 'preserves complete ordered violations and evidence from uncached pure projections' do
    projection = ArchUnit::Common::Projection
    graph = ArchUnit::Extraction.extract_graph(@root)
    legacy = Struct.new(:nodes, :internal_edges, :external_edges).new(
      projection.project_to_nodes(graph),
      projection.project_edges(graph, projection.per_internal_edge),
      projection.project_edges(graph, projection.per_external_edge)
    )
    rules = dependency_rules + other_rules
    allow(ArchUnit::Extraction).to receive(:extract_graph_views).and_return(legacy)
    expected = rules.map(&:check)
    allow(ArchUnit::Extraction).to receive(:extract_graph_views).and_call_original
    2.times { expect(rules.map(&:check)).to eq(expected) }
    expect(expected.map(&:length)).to eq([1, 1, 1, 1, 1, 1, 1, 1])
  end

  it 'shares invariant work across different file and layer checks, not their selectors' do
    projection = ArchUnit::Common::Projection
    expect(projection).to receive(:project_to_nodes).once.and_call_original
    expect(projection).to receive(:project_edges).with(anything, anything).twice.and_call_original
    rules = dependency_rules + other_rules
    2.times { rules.each(&:check) }
  end

  it 'repeats stateful predicates and reads current FileInfo content on every check' do
    seen = []
    predicate = lambda do |file|
      seen << file.content
      file.content.include?('no imports')
    end
    rule = ArchUnit.files(@root).with_name('isolated.rb').should
                   .adhere_to(predicate, 'keeps marker')
    expect(rule.check).to be_empty
    File.write(File.join(@root, 'isolated.rb'), '# changed')
    expect(rule.check.length).to eq(1)
    expect(seen).to eq(['# no imports', '# changed'])
  end

  it 'does not memoize custom slice labelers with mutable captured state' do
    state = { selected: true, calls: 0 }
    projection = ArchUnit::SliceProjection.new do |path|
      state[:calls] += 1
      path if state[:selected]
    end
    scope = ArchUnit::Slices::FluentApi::SliceScopeBuilder.new(project_locator: @root, projection:)
    rule = scope.should_not.contain_dependency('a.rb', 'b.rb')
    expect(rule.check.length).to eq(1)
    calls = state[:calls]
    state[:selected] = false
    expect(rule.check.first).to be_a(ArchUnit::EmptyTestViolation)
    expect(state[:calls]).to be > calls
  end

  it 'logs each check separately when fibers and threads share an already indexed graph' do
    dependency_rules.first.check
    work = lambda do
      output = StringIO.new
      options = ArchUnit::CheckOptions.new(logging: ArchUnit::LoggingOptions.new(
        io: output, level: :debug
      ))
      dependency_rules.first.check(options)
      output.string.gsub(/\A\[[^\]]+\] /, '').gsub(/\n\[[^\]]+\] /, "\n")
    end
    outputs = [Fiber.new { work.call }.resume, Thread.new { work.call }.value, work.call]
    expect(outputs.uniq.length).to eq(1)
    expect(outputs.first.scan('selected file count: 1').length).to eq(1)
    expect(ArchUnit::Common::Logging::Inspection.logger).to be_nil
  end

  it 'replaces all cached views between CLI commands in the same process' do
    File.write(File.join(@root, '.archunit.rb'), <<~RUBY)
      rule('boundary') { project_files.with_name('a.rb').should_not.depend_on_files.with_name('b.rb') }
    RUBY
    args = ['check', '--format', 'json']
    expect(ArchUnit::CLI.run(args, out: StringIO.new, err: StringIO.new, cwd: @root)).to eq(1)
    old = ArchUnit::Extraction.extract_graph_views(@root)
    File.write(File.join(@root, 'a.rb'), '# fixed')
    expect(ArchUnit::CLI.run(args, out: StringIO.new, err: StringIO.new, cwd: @root)).to eq(0)
    expect(ArchUnit::Extraction.extract_graph_views(@root)).not_to equal(old)
  end
end
