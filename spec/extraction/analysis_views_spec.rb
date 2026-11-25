# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'
require 'weakref'

RSpec.describe ArchUnit::Extraction, 'analysis-owned views' do
  around do |example|
    Dir.mktmpdir('archunit-analysis-views') do |root|
      @root = root
      File.write(File.join(root, 'a.rb'), "require_relative 'b'\nrequire 'json'\n::B")
      File.write(File.join(root, 'b.rb'), 'class B; end')
      described_class.clear_graph_cache
      example.run
    ensure
      described_class.clear_graph_cache
    end
  end

  def views(options = nil, root: @root)
    described_class.extract_graph_views(root, options:)
  end

  def view_references
    bundle = views
    bundle.nodes
    [WeakRef.new(bundle), bundle.graph]
  end

  it 'shares one lazy bundle with the existing graph snapshot and execution-only options' do
    first = views
    expect(first.graph).to equal(described_class.extract_graph(@root))
    options = ArchUnit::CheckOptions.new(allow_empty_tests: true)
    expect(views(options)).to equal(first)
    expect(views.nodes).to equal(first.nodes)
  end

  it 'keeps old views until explicit rebuild, even after an on-disk edit' do
    first = views
    first.nodes
    File.write(File.join(@root, 'new.rb'), '# new node')
    expect(views).to equal(first)
    rebuilt = views(ArchUnit::CheckOptions.new(clear_cache: true))
    expect(rebuilt).not_to equal(first)
    expect(rebuilt.nodes.map(&:label)).to include('new.rb')
    expect(first.nodes.map(&:label)).not_to include('new.rb')
  end

  it 'global clearing releases the cache-owned bundle even while the old graph is held' do
    old = views
    graph = old.graph
    old.internal_edges
    ArchUnit.clear_graph_cache
    rebuilt = views
    expect(rebuilt).not_to equal(old)
    expect(rebuilt.graph).not_to equal(graph)
    expect(rebuilt.internal_edges).to eq(old.internal_edges)
  end

  it 'does not keep an index alive through the graph after the cache is cleared' do
    weak, graph = view_references
    ArchUnit.clear_graph_cache
    GC.start
    expect(weak.weakref_alive?).to be_falsey
    expect(graph).not_to be_empty
  end

  it 'separates analysis modes, Rails imports, explicit load paths and source exclusions' do
    first = views
    settings = [{ dependency_analysis: :imports_and_constants }, { rails_imports: true },
                { load_paths: ['.'] }, { source_exclusions: ['b.rb'] }]
    settings.each do |attributes|
      options = ArchUnit::CheckOptions.new(**attributes)
      expect(views(options)).not_to equal(first)
      expect(views(options)).to equal(views(options))
    end
    excluded = views(ArchUnit::CheckOptions.new(source_exclusions: ['b.rb']))
    expect(excluded.nodes.map(&:label)).to eq(['a.rb'])
    expect(views.nodes.map(&:label)).to eq(%w[a.rb b.rb])
  end

  it 'isolates roots and preserves unrelated views on per-entry invalidation' do
    Dir.mktmpdir('archunit-other-views') do |other|
      File.write(File.join(other, 'other.rb'), '# other')
      first = views
      unrelated = views(root: other)
      expect(unrelated).not_to equal(first)
      views(ArchUnit::CheckOptions.new(clear_cache: true))
      expect(views(root: other)).to equal(unrelated)
      expect(unrelated.nodes.map(&:label)).to eq(['other.rb'])
    end
  end

  it 'invalidates bundle identity when the project ignore file changes' do
    first = views
    File.write(File.join(@root, '.archignore'), "b.rb\n")
    expect(views).not_to equal(first)
    expect(views.nodes.map(&:label)).to eq(['a.rb'])
  end

  it 'uses distinct views for direct exclusion sets and normalizes equivalent sets' do
    first = views
    filtered = described_class.extract_graph_views(@root, exclude_patterns: ['b.rb'])
    equivalent = described_class.extract_graph_views(@root, exclude_patterns: %w[b.rb b.rb])
    expect(filtered).not_to equal(first)
    expect(equivalent).to equal(filtered)
    expect(filtered.nodes.map(&:label)).to eq(['a.rb'])
  end
end
