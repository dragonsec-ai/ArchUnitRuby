# frozen_string_literal: true

RSpec.describe 'Immutable graph views' do
  let(:projection) { ArchUnit::Common::Projection }
  let(:edges) do
    [['isolated.rb', 'isolated.rb', false], ['a.rb', 'a.rb', false],
     ['a.rb', 'b.rb', false], ['a.rb', 'json', true]].map do |source, target, external|
      ArchUnit::Edge.new(source:, target:, external:)
    end
  end
  let(:graph) { ArchUnit::Common::Extraction::Graph.new(edges) }
  let(:views) { ArchUnit::Extraction.const_get(:GraphViews).new(graph) }

  it 'does no projection work until a specific view is requested' do
    expect(projection).not_to receive(:project_to_nodes)
    expect(projection).not_to receive(:project_edges)
    expect(views.graph).to equal(graph)
    expect(views).to be_frozen
  end

  it 'projects each built-in view once and shares the immutable results' do
    expect(projection).to receive(:project_to_nodes).with(graph).once.and_call_original
    expect(projection).to receive(:project_edges).with(graph, anything).twice.and_call_original
    %i[nodes internal_edges external_edges].each do |name|
      first = views.public_send(name)
      expect(first).to be_frozen
      expect(views.public_send(name)).to equal(first)
    end
  end

  it 'preserves isolated nodes, outgoing externals and distinct edge semantics' do
    expect(views.nodes.map(&:label)).to eq(%w[a.rb b.rb isolated.rb])
    expect(views.nodes.first.outgoing.map(&:target)).to eq(%w[b.rb json])
    expect(views.internal_edges.map(&:target_label)).to eq(['b.rb'])
    expect(views.external_edges.map(&:target_label)).to eq(['json'])
    expect(views.nodes.flat_map { |node| [node.incoming, node.outgoing] }).to all(be_frozen)
    expect(views.internal_edges.map(&:cumulated_edges)).to all(be_frozen)
    expect(views.internal_edges.first.cumulated_edges.first).to equal(edges[2])
  end

  it 'serializes concurrent first use without duplicating projections' do
    expect(projection).to receive(:project_to_nodes).once.and_call_original
    results = Array.new(8) { Thread.new { Array.new(5) { views.nodes } } }.flat_map(&:value)
    expect(results.map(&:object_id).uniq.length).to eq(1)
  end

  it 'keeps a same-spelled external import without inventing an incoming edge' do
    dependency = ArchUnit::Edge.new(source: 'a.rb', target: 'a.rb', external: true)
    edges << dependency
    node = views.nodes.find { |item| item.label == 'a.rb' }
    expect(node.outgoing).to include(dependency)
    expect(node.incoming).to be_empty
    expect(views.external_edges.flat_map(&:cumulated_edges)).to include(dependency)
    expect(views.internal_edges.flat_map(&:cumulated_edges)).not_to include(dependency)
  end

  it 'does not retain a failed projection as a successful empty view' do
    calls = 0
    allow(projection).to receive(:project_to_nodes).and_wrap_original do |original, *args|
      calls += 1
      raise 'projection failed' if calls == 1

      original.call(*args)
    end
    expect { views.nodes }.to raise_error('projection failed')
    expect(views.nodes.map(&:label)).to include('isolated.rb')
    expect(calls).to eq(2)
  end
end
