# frozen_string_literal: true

RSpec.describe ArchUnit::Common::Projection, '.project_cycles' do
  def raw_edge(source, target, external: false, kind: :require)
    ArchUnit::Edge.new(source:, target:, external:, import_kinds: [kind])
  end

  def projected_edge(source, target, raw: raw_edge(source, target))
    ArchUnit::ProjectedEdge.new(
      source_label: source, target_label: target, cumulated_edges: [raw]
    )
  end

  it 'returns every projected edge in cyclic order with raw evidence intact' do
    first = projected_edge('api', 'domain')
    second = projected_edge('domain', 'persistence')
    third = projected_edge('persistence', 'api')

    cycles = described_class.project_cycles([first, second, third])

    expect(cycles).to eq([[first, second, third]])
    expect(cycles).to be_frozen
    expect(cycles.first).to be_frozen
    expect(cycles.first.flat_map(&:cumulated_edges)).to eq(
      [first, second, third].flat_map(&:cumulated_edges)
    )
  end

  it 'filters projected self-edges and returns an immutable empty result' do
    self_edge = projected_edge('api', 'api')

    cycles = described_class.project_cycles([self_edge])

    expect(cycles).to eq([])
    expect(cycles).to be_frozen
  end

  it 'cumulates duplicate projected label pairs before finding cycles' do
    first_raw = raw_edge('a/first.rb', 'b/target.rb')
    second_raw = raw_edge('a/second.rb', 'b/target.rb', kind: :load)
    first = projected_edge('a', 'b', raw: first_raw)
    duplicate = projected_edge('a', 'b', raw: second_raw)
    reverse = projected_edge('b', 'a')

    cycle = described_class.project_cycles([first, duplicate, reverse]).fetch(0)
    forward = cycle.find { |edge| edge.source_label == 'a' }

    expect(forward.cumulated_edges).to eq([first_raw, second_raw])
  end

  it 'finds only cycles made from non-external raw graph dependencies' do
    forward = raw_edge('a.rb', 'b.rb')
    reverse = raw_edge('b.rb', 'a.rb')
    external = raw_edge('a.rb', 'json', external: true)

    cycles = described_class.project_internal_cycles([forward, reverse, external])

    expect(cycles.length).to eq(1)
    expect(cycles.first.map { |edge| [edge.source_label, edge.target_label] }).to eq(
      [['a.rb', 'b.rb'], ['b.rb', 'a.rb']]
    )
  end

  it 'rejects invalid projected graphs' do
    expect { described_class.project_cycles(Object.new) }
      .to raise_error(ArgumentError, /enumerable of ProjectedEdge/)
    expect { described_class.project_cycles([Object.new]) }
      .to raise_error(ArgumentError, /only ProjectedEdge/)
  end

  it 'reports exactly one stable closed path per cyclic group with all its edge evidence' do
    a_to_b = projected_edge('a', 'b')
    duplicate = projected_edge('a', 'b', raw: raw_edge('a/helper.rb', 'b/main.rb', kind: :load))
    reverse = projected_edge('b', 'a')
    edges = [a_to_b, duplicate, reverse, projected_edge('b', 'c'), projected_edge('c', 'a'),
             projected_edge('c', 'd'), projected_edge('d', 'e'), projected_edge('e', 'd'),
             projected_edge('f', 'f'), projected_edge('f', 'a')]

    paths = [%w[a b], %w[d e]]
    [edges, edges.reverse, edges.shuffle(random: Random.new(42))].each do |order|
      witnesses = described_class.project_cycle_witnesses(order)
      expect(witnesses.map { |cycle| cycle.map(&:source_label) }).to eq(paths)
      expect(witnesses).to be_frozen
      expect(witnesses).to all(be_frozen)
      raw = witnesses.first.first.cumulated_edges
      expect(raw).to match_array(a_to_b.cumulated_edges + duplicate.cumulated_edges)
      expect(witnesses.first.last).to eq(reverse)
    end
  end

  it 'uses an SCC pass without enumerating the thousands of paths in a dense cyclic group' do
    labels = (0...14).map { |index| format('file-%02d', index) }
    edges = labels.combination(2).map { |source, target| projected_edge(source, target) }
    edges << projected_edge(labels.last, labels.first)
    expect(described_class.project_cycles(edges).length).to eq(4096)
    expect(described_class::Cycles::JohnsonCycles).not_to receive(:call)
    expect(described_class::Cycles::TarjanScc).to receive(:call).once.and_call_original
    expect(described_class.project_cycle_witnesses(edges).first&.map(&:source_label))
      .to eq([labels[0], labels[1], labels.last])
  end

  it 'returns no witnesses for an acyclic or self-only selected graph' do
    edges = [projected_edge('a', 'b'), projected_edge('b', 'c'), projected_edge('c', 'c')]
    expect(described_class.project_cycle_witnesses(edges)).to eq([])
  end
end
