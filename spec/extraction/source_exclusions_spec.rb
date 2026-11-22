# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'tmpdir'

RSpec.describe 'caller-owned source exclusions' do
  around do |example|
    Dir.mktmpdir('archunit-source-exclusions') do |directory|
      @root = File.realpath(directory)
      source('Gemfile', "raise 'must not execute Gemfile'\n")
      source('app/api/request.rb', "require_relative '../db/store'\nclass Request; end\n")
      source('app/db/store.rb', "class Store; end\nraise 'must not execute application code'\n")
      source('lib/generators/templates/migration.rb', '<%= migration_class_name %>')
      source('lib/templates/real.rb', 'class RealRuby; end')
      ArchUnit.clear_graph_cache
      example.run
    ensure
      ArchUnit.clear_graph_cache
    end
  end

  def source(path, code)
    file = File.join(@root, path)
    FileUtils.mkdir_p(File.dirname(file))
    File.write(file, code)
    file
  end

  def options(mode = :imports)
    ArchUnit::CheckOptions.new(
      dependency_analysis: mode,
      source_exclusions: ['lib/generators/templates/migration.rb']
    )
  end

  def forbidden
    ArchUnit.project_files(@root).in_path('app/api/**')
            .should_not.depend_on_files.in_path('app/db/**')
  end

  %i[imports imports_and_constants].each do |mode|
    it "excludes only explicit templates in #{mode}, without editing target source or policy" do
      original = File.binread(File.join(@root, 'lib/generators/templates/migration.rb'))
      expect { forbidden.check }.to raise_error(ArchUnit::SourceParseError)
      expect(forbidden.check(options(mode)).length).to eq(1)
      graph = ArchUnit::Extraction.extract_graph(@root, options: options(mode))
      expect(graph.map(&:source).uniq).to contain_exactly(
        'app/api/request.rb', 'app/db/store.rb', 'lib/templates/real.rb'
      )
      template = File.join(@root, 'lib/generators/templates/migration.rb')
      expect(File.binread(template)).to eq(original)
      expect(File.exist?(File.join(@root, '.archignore'))).to be(false)
      json = ArchUnit.project_graph(@root).with_check_options(options(mode)).to_json
      expect(JSON.parse(json).fetch('summary').fetch('node_count')).to eq(3)
      expect(json).not_to include('lib/generators/templates/migration.rb')
    end
  end

  it 'shares the same caller policy across counts, cohesion, coupling and metric reports' do
    selected = ArchUnit.metrics(@root)
    counts = selected.count.classes.measure(options)
    expect(counts.map { |item| item.subject.path }).to contain_exactly(
      'app/api/request.rb', 'app/db/store.rb', 'lib/templates/real.rb'
    )
    expect(selected.lcom.lcom4.measure(options).length).to eq(3)
    expect(selected.distance.instability.measure(options).length).to eq(3)
    expect(selected.count.classes.should_be_above_or_equal(0).check(options)).to be_empty
    project = ArchUnit::MetricExtraction.extract_project_info(@root, options:)
    expect(project.files.length).to eq(3)
    expect(selected.analyze(options).files.length).to eq(3)
    output = File.join(@root, 'pkg/metrics.html')
    FileUtils.mkdir_p(File.dirname(output))
    export = ArchUnit::MetricsExportOptions.new(check_options: options, include_timestamp: false)
    selected.count.export_as_html(output, export)
    expect(File.read(output)).to include('app/api/request.rb')
    expect(File.read(output)).not_to include('lib/generators/templates/migration.rb')
  end

  it 'merges caller exclusions with defaults and repository policy, not in place of them' do
    source('vendor/dependency.rb', 'class VendorDependency; end')
    source('generated/ignored.rb', '<%= invalid template %>')
    source('.archignore', 'generated/')
    files = ArchUnit::Extraction.enumerate_source_files(@root, options:)
    expect(files).not_to include('vendor/dependency.rb', 'generated/ignored.rb')
    expect(File.read(File.join(@root, '.archignore'))).to eq('generated/')
    legacy = ArchUnit::Extraction.enumerate_source_files(@root, exclude_patterns: [], options:)
    expect(legacy).to include('vendor/dependency.rb')
    expect(legacy).not_to include('generated/ignored.rb', 'lib/generators/templates/migration.rb')
  end

  it 'uses normalized effective exclusions in cache identity and preserves cache refresh' do
    first = ArchUnit::Extraction.extract_graph(@root, options:)
    equivalent = options.with(source_exclusions: ['./lib/generators/templates/migration.rb'])
    expect(ArchUnit::Extraction.extract_graph(@root, options: equivalent)).to equal(first)
    patterns = [*ArchUnit::Extraction::DEFAULT_EXCLUDED_DIRECTORIES,
                'lib/generators/templates/migration.rb']
    expect(ArchUnit::Extraction.extract_graph(@root, exclude_patterns: patterns)).to equal(first)
    refreshed = ArchUnit::Extraction.extract_graph(@root, options: options.with(clear_cache: true))
    expect(refreshed).not_to equal(first)
    expect { ArchUnit::Extraction.extract_graph(@root) }.to raise_error(ArchUnit::SourceParseError)
  end

  it 'keeps malformed application files fatal and empty selections as violations' do
    source('app/broken.rb', 'class Broken <')
    expect { forbidden.check(options) }.to raise_error(ArchUnit::SourceParseError)
    expect { ArchUnit.metrics(@root).count.classes.measure(options) }
      .to raise_error(ArchUnit::SourceParseError)
    empty = options.with(source_exclusions: ['**/*.rb'])
    expect(forbidden.check(empty)).to contain_exactly(an_instance_of(ArchUnit::EmptyTestViolation))
  end
end
