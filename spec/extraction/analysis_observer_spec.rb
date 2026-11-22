# frozen_string_literal: true

require 'archunit/cli'
require 'fileutils'
require 'pathname'
require 'tmpdir'

RSpec.describe ArchUnit::Extraction::AnalysisObserver do
  let(:expanded) { ArchUnit::CheckOptions.new(dependency_analysis: :imports_and_constants) }

  around do |example|
    Dir.mktmpdir('archunit-analysis') do |directory|
      @root = Pathname.new(directory).realpath
      @root.join('Gemfile').write("raise 'never boot this project'")
      source('app.rb', "require plugin_path\nMissing\nDb\nraise 'never execute source'")
      source('lib/one.rb', 'module Db; end')
      source('lib/two.rb', 'module Db; end')
      example.run
    ensure
      ArchUnit.clear_graph_cache
    end
  end

  def source(path, contents)
    file = @root.join(path)
    FileUtils.mkdir_p(file.dirname)
    file.write(contents)
  end

  def capture
    report = ArchUnit::CLI::AnalysisReport.new
    described_class.capture(report) { yield report }
    report
  end

  it 'exposes independent immutable counters without requiring a public timing profile' do
    report = capture { ArchUnit::Extraction.extract_graph(@root, options: expanded) }
    scope = report.to_h.fetch(:scopes).first
    expect(scope).to include(kind: 'dependency_graph', dependency_analysis: 'imports_and_constants')
    expect(scope[:counters]).to eq(
      source_files: 3, imports: 0, unresolved_imports: 1,
      unresolved_constant_references: 1, ambiguous_constant_references: 1
    )
    expect(scope[:counters]).to be_frozen
    expect(scope[:effective_source_exclusions]).to be_frozen
  end

  it 'distinguishes unperformed constant analysis from measured zero counts' do
    report = capture { ArchUnit::Extraction.extract_graph(@root) }
    expect(report.to_h[:scopes].first[:counters]).to include(
      unresolved_imports: 1, unresolved_constant_references: nil, ambiguous_constant_references: nil
    )
    source('app.rb', '# no dependencies')
    report = capture { ArchUnit::Extraction.extract_graph(@root, options: expanded) }
    expect(report.to_h[:scopes].first[:counters]).to include(
      unresolved_imports: 0, unresolved_constant_references: 0, ambiguous_constant_references: 0
    )
  end

  it 'exposes conservative inherited lookup without hiding the resolvable root-qualified control' do
    source('app.rb', 'class Child < Parent; Service; ::Service; end')
    source('lib/one.rb', 'class Parent; end')
    source('lib/two.rb', 'class Service; end')
    graph = nil
    report = capture { graph = ArchUnit::Extraction.extract_graph(@root, options: expanded) }
    expect(report.to_h[:scopes].first[:counters]).to include(
      unresolved_constant_references: 1, ambiguous_constant_references: 0
    )
    evidence = graph.flat_map(&:evidence).map(&:name)
    expect(evidence).to include('Parent', '::Service')
    expect(evidence).not_to include('Service')
  end

  it 'reports a measured empty graph as zero sources rather than unavailable analysis' do
    report = capture do
      rule = ArchUnit.project_files(@root).should.have_no_cycles
      violations = rule.check(ArchUnit::CheckOptions.new(source_exclusions: ['**/*.rb']))
      expect(violations).to all(be_a(ArchUnit::Common::Assertion::EmptyTestViolation))
      expect(violations.length).to eq(1)
    end
    expect(report.to_h[:scopes].first[:counters]).to include(source_files: 0, unresolved_imports: 0)
  end

  it 'retains cold counts for a graph cached before capture without faking warm activity' do
    graph = ArchUnit::Extraction.extract_graph(@root, options: expanded)
    profile = ArchUnit::Extraction::ExtractionProfile.new
    report = capture do |analysis|
      %w[first second].each do |name|
        analysis.for_rule(name) do
          expect(ArchUnit::Extraction.extract_graph(@root, options: expanded,
                                                           profile:)).to equal(graph)
        end
      end
    end
    expect(profile).to be_cache_hit
    expect(profile.counters.values).to all(be_zero)
    expected = { cache_hits: 2, observations: 2, rule_names: %w[first second],
                 counters: include(source_files: 3, unresolved_imports: 1) }
    expect(report.to_h[:scopes]).to contain_exactly(include(expected))
    expect(report.for_name('second')).to eq(status: 'available', scope_ids: [1])
  end

  it 'does not let a caller profile shared across roots inflate either analysis snapshot' do
    nested = @root.join('other')
    source('other/Gemfile', '# marker')
    source('other/item.rb', 'class Item; end')
    profile = ArchUnit::Extraction::ExtractionProfile.new
    report = capture do
      ArchUnit::Extraction.extract_graph(@root, exclude_patterns: ['other'], profile:)
      ArchUnit::Extraction.extract_graph(nested, profile:)
    end
    expect(profile.counters[:source_files]).to eq(4)
    expect(report.to_h[:scopes].map { |scope| scope[:counters][:source_files] }).to eq([3, 1])
  end

  it 'keeps distinct policies, analysis modes, and refreshed snapshots separate' do
    narrowed = expanded.with(source_exclusions: ['lib/two.rb'], rails_imports: true,
                             load_paths: ['lib'])
    report = capture do |analysis|
      analysis.for_rule('all') { ArchUnit::Extraction.extract_graph(@root, options: expanded) }
      analysis.for_rule('narrow') { ArchUnit::Extraction.extract_graph(@root, options: narrowed) }
      analysis.for_rule('imports') { ArchUnit::Extraction.extract_graph(@root) }
      source('extra.rb', '# a new file')
      analysis.for_rule('fresh') do
        ArchUnit::Extraction.extract_graph(@root, options: expanded.with(clear_cache: true))
      end
    end
    scopes = report.to_h[:scopes]
    expect(scopes.map { |scope| scope[:counters][:source_files] }).to eq([3, 2, 3, 4])
    expect(report.for_name('all')[:scope_ids]).to eq([1])
    expect(report.for_name('fresh')[:scope_ids]).to eq([4])
    expect(scopes[1][:effective_source_exclusions]).to include('lib/two.rb')
    expect(scopes[1]).to include(rails_imports: true, load_paths: ['lib'])
    expect(report.to_h).not_to have_key(:total_source_files)
  end

  it 'describes metric-only analysis without inventing dependency counts or modes' do
    report = capture do
      options = expanded.with(source_exclusions: ['lib/two.rb'])
      ArchUnit.metrics(@root).count.classes.measure(options)
    end
    counters = { source_files: 2, imports: nil, unresolved_imports: nil,
                 unresolved_constant_references: nil, ambiguous_constant_references: nil }
    scopes = report.to_h[:scopes]
    expect(scopes.length).to eq(1)
    expect(scopes.first).to include(kind: 'source_metrics', dependency_analysis: nil, counters:)
  end

  it 'records the exact metric source policy rather than rereading it after parsing' do
    @root.join('.archignore').write('lib/two.rb')
    extractor = ArchUnit::Metrics::Extraction
    allow(extractor).to receive(:extract_file_info).and_wrap_original do |original, *args, **kw|
      @root.join('.archignore').write('lib/one.rb')
      original.call(*args, **kw)
    end
    report = capture { ArchUnit.metrics(@root).count.classes.measure }
    scope = report.to_h[:scopes].first
    expect(scope[:effective_source_exclusions]).to include('lib/two.rb')
    expect(scope[:effective_source_exclusions]).not_to include('lib/one.rb')
    expect(scope[:counters][:source_files]).to eq(2)
  end

  %i[graph metrics].each do |kind|
    it "keeps #{kind} parse errors fatal with unavailable counts" do
      source('broken.rb', 'class Broken <')
      report = ArchUnit::CLI::AnalysisReport.new
      expect do
        described_class.capture(report) do
          if kind == :graph
            ArchUnit::Extraction.extract_graph(@root)
          else
            ArchUnit.metrics(@root).count.classes.measure
          end
        end
      end.to raise_error(ArchUnit::SourceParseError)
      expect(report.to_h[:status]).to eq('partial')
      scopes = report.to_h[:scopes]
      expect(scopes.length).to eq(1)
      expect(scopes.first).to include(status: 'error')
      expect(scopes.first[:counters].values).to all(be_nil)
    end
  end

  it 'restores nested observers after exceptions and does not leak across threads or fibers' do
    outer = ArchUnit::CLI::AnalysisReport.new
    inner = ArchUnit::CLI::AnalysisReport.new
    described_class.capture(outer) do
      expect do
        described_class.capture(inner) do
          ArchUnit::Extraction.extract_graph(@root)
          raise 'stop'
        end
      end.to raise_error('stop')
      Thread.new { ArchUnit::Extraction.extract_graph(@root) }.value
      Fiber.new { ArchUnit::Extraction.extract_graph(@root) }.resume
      ArchUnit::Extraction.extract_graph(@root)
    end
    ArchUnit::Extraction.extract_graph(@root)
    expect(outer.to_h[:scopes].first[:observations]).to eq(1)
    expect(inner.to_h[:scopes].first[:observations]).to eq(1)
  end

  it 'notifies outside the cache mutex so observers may safely query the graph' do
    nested = false
    observer = Object.new
    root = @root
    observer.define_singleton_method(:observe) do |_snapshot, **_settings|
      return if nested

      nested = true
      ArchUnit::Extraction.extract_graph(root)
    end
    described_class.capture(observer) { ArchUnit::Extraction.extract_graph(@root) }
    expect(nested).to be(true)
  end
end
