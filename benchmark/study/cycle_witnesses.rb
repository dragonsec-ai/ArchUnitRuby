# frozen_string_literal: true

require 'archunit'
require 'json'

# Small, fixed graphs with an independently known exponential number of simple cycles.
module CycleWitnessStudy
  PROJECTION = ArchUnit::Common::Projection
  private_constant :PROJECTION

  module_function

  def run
    cases = [10, 14, 18].map { |size| measure(size) }
    puts JSON.pretty_generate(ruby: RUBY_DESCRIPTION, runs_per_mode: 3, cases:)
  end

  def measure(size)
    labels = (0...size).map { |index| format('file-%02d.rb', index) }
    graph = fixture(labels)
    samples = collect(graph, labels)
    { vertices: size, edges: graph.length, modes: samples.transform_values { |rows| median(rows) } }
  end

  def collect(graph, labels)
    counts = { exhaustive: 2**(labels.length - 2), witness: 1 }
    samples = { exhaustive: [], witness: [] }
    3.times do |iteration|
      order = iteration.odd? ? counts.keys.reverse : counts.keys
      order.each { |mode| samples.fetch(mode) << sample(graph, labels, mode, counts.fetch(mode)) }
    end
    samples
  end

  def fixture(labels)
    pairs = labels.combination(2).to_a << [labels.last, labels.first]
    raw = pairs.map { |source, target| ArchUnit::Edge.new(source:, target:, external: false) }
    PROJECTION.project_edges(raw, PROJECTION.per_internal_edge)
  end

  def sample(graph, labels, mode, count)
    GC.start
    allocations = GC.stat(:total_allocated_objects)
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    cycles = project(graph, mode)
    seconds = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
    allocated = GC.stat(:total_allocated_objects) - allocations
    validate(cycles, labels, mode, count)
    { milliseconds: (seconds * 1000).round(3), allocations: allocated,
      reported_paths: cycles.length, reported_edge_steps: cycles.sum(&:length) }
  end

  def project(graph, mode)
    mode == :witness ? PROJECTION.project_cycle_witnesses(graph) : PROJECTION.project_cycles(graph)
  end

  def validate(cycles, labels, mode, count)
    abort "wrong count for #{mode}" unless cycles.length == count
    return unless mode == :witness

    path = cycles.fetch(0).map(&:source_label)
    abort 'wrong path for witness' unless path == [labels[0], labels[1], labels.last]
  end

  def median(rows)
    rows.first.keys.to_h { |key| [key, rows.map { |row| row.fetch(key) }.sort.fetch(1)] }
  end
end

CycleWitnessStudy.run
