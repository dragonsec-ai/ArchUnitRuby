# frozen_string_literal: true

require 'archunit/cli'

RSpec.describe ArchUnit::CLI::BaselineFingerprint do
  let(:context) { [{ 'root' => '.', 'dependency_analysis' => 'imports' }] }

  def edge(source = 'app/api.rb', target = 'app/db.rb', external: false)
    raw = ArchUnit::Common::Extraction::Edge.new(source:, target:, external:)
    ArchUnit::Common::Projection::ProjectedEdge.new(source_label: source, target_label: target,
                                                    cumulated_edges: [raw])
  end

  def fingerprint(violation, name: 'boundary')
    described_class.entry(name, violation, context).fetch('fingerprint')
  end

  it 'explicitly fingerprints dependency, layer, slice, pattern and numeric-threshold data' do
    filter = ArchUnit::Common::RegexFactory.filename_matcher('allowed.rb', except: '*.legacy.rb')
    node = ArchUnit::Common::Projection::ProjectedNode.new(label: 'app/api.rb')
    subject = Data.define(:identifier).new(identifier: 'app/api.rb')
    violations = [
      ArchUnit::Files::Assertion::FileDependencyViolation.new(dependency: edge, is_negated: true),
      ArchUnit::Files::Assertion::ExternalModuleDependencyViolation.new(
        dependency: edge('app/api.rb', 'json', external: true)
      ),
      ArchUnit::Layers::Assertion::LayerDependencyViolation.new(
        dependency: edge, source_layer: 'api', target_layer: 'db', rule: :may_not_depend_on_layers
      ),
      ArchUnit::Slices::Assertion::SliceDependencyViolation.new(
        dependency: edge, source_slice: 'api', target_slice: 'db', rule: :contain_dependency,
        is_negated: true
      ),
      ArchUnit::Files::Assertion::FilePatternViolation.new(check_filter: filter,
                                                           projected_node: node),
      ArchUnit::Metrics::Assertion::MetricThresholdViolation.new(
        subject:, metric_name: :classes, value: 3, threshold: 2, comparison: :below
      )
    ]
    ids = violations.map { |violation| fingerprint(violation) }
    expect(ids.uniq.length).to eq(violations.length)
    expect(ids).to all(match(/\A[a-f0-9]{64}\z/))
  end

  it 'canonicalizes directed cycle rotations without reversing the direction' do
    edges = [edge('a.rb', 'b.rb'), edge('b.rb', 'c.rb'), edge('c.rb', 'a.rb')]
    first = ArchUnit::Files::Assertion::CycleViolation.new(cycle: edges)
    rotated = ArchUnit::Files::Assertion::CycleViolation.new(cycle: edges.rotate(1))
    expect(fingerprint(first)).to eq(fingerprint(rotated))
    reversed = [edge('a.rb', 'c.rb'), edge('c.rb', 'b.rb'), edge('b.rb', 'a.rb')]
    backwards = ArchUnit::Files::Assertion::CycleViolation.new(cycle: reversed)
    expect(fingerprint(first)).not_to eq(fingerprint(backwards))
    repeated = ArchUnit::Files::Assertion::CycleViolation.new(cycle: edges * 2)
    expect(described_class.entry('repeated', repeated, context)).to be_nil
  end

  it 'ignores edge order and source evidence locations but not changed dependencies or rules' do
    first = ArchUnit::Files::Assertion::FileDependencyViolation.new(dependency: edge)
    other = ArchUnit::Files::Assertion::FileDependencyViolation.new(dependency: edge('app/api.rb',
                                                                                     'other.rb'))
    expect(fingerprint(first)).not_to eq(fingerprint(other))
    expect(fingerprint(first, name: 'renamed')).not_to eq(fingerprint(first))
    raw = edge.cumulated_edges.first
    evidence = ArchUnit::Common::Extraction::DependencyEvidence.new(
      source: raw.source, kind: :require, name: 'db', line_number: 100, end_line: 100
    )
    located = raw.with(evidence: [evidence])
    projected = edge.with(cumulated_edges: [located])
    moved = ArchUnit::Files::Assertion::FileDependencyViolation.new(dependency: projected)
    expect(fingerprint(moved)).to eq(fingerprint(first))
  end

  it 'rejects empty selections, unrecognized/custom subclasses and unobserved scopes' do
    empty = ArchUnit::Common::Assertion::EmptyTestViolation.new(filters: [])
    expect(described_class.entry('typo', empty, context)).to be_nil
    custom = Class.new(ArchUnit::Files::Assertion::FileDependencyViolation).new(dependency: edge)
    expect(described_class.entry('custom', custom, context)).to be_nil
    normal = ArchUnit::Files::Assertion::FileDependencyViolation.new(dependency: edge)
    expect(described_class.entry('no scope', normal, nil)).to be_nil
    absolute = ArchUnit::Files::Assertion::FileDependencyViolation.new(
      dependency: edge('C:/outside.rb', 'db.rb')
    )
    expect { fingerprint(absolute) }.to raise_error(ArgumentError, /project-relative/)
  end

  it 'canonicalizes hash order and leaves caller-owned entries unchanged' do
    entry = { 'rule' => 'a', 'data' => { 'b' => 1, 'a' => [2, 3] } }
    original = Marshal.load(Marshal.dump(entry))
    reversed = { 'data' => { 'a' => [2, 3], 'b' => 1 }, 'rule' => 'a' }
    expect(described_class.digest(entry)).to eq(described_class.digest(reversed))
    expect(entry).to eq(original)
  end
end
