# frozen_string_literal: true

require 'json'
require 'objspace'
require 'pathname'
require 'tmpdir'

# Reproducible opt-in timing; the completed selection is checked against a known chain.
module DeclarationSelectionStudy
  FILES = 500
  TRIALS = 5

  module_function

  def run
    startup = measure_default_load
    Dir.mktmpdir('archunit-declarations-bench') do |directory|
      root = Pathname.new(directory)
      fixture(root)
      setup = measure { ArchUnit.project_classes(root) }
      scope = ArchUnit.project_classes(root).descendants_of('Node0')
      data = { ruby: RUBY_DESCRIPTION, files: FILES, trials: TRIALS, startup:, setup: }
      puts JSON.pretty_generate(data.merge(benchmarks(scope)))
    end
  end

  def measure_default_load
    startup = measure { require 'archunit' }
    loaded = ArchUnit::Extraction.respond_to?(:extract_declarations)
    raise 'default load built declarations' if loaded

    startup
  end

  def fixture(root)
    root.join('Gemfile').write("raise 'do not boot fixture'")
    FILES.times do |index|
      parent = index.zero? ? '' : " < ::Node#{index - 1}"
      root.join("node#{index}.rb").write("class Node#{index}#{parent}; def call(id); end; end")
    end
  end

  def benchmarks(scope)
    cold, warm, retained = samples(scope)
    { cold_median: median(cold), warm_median: median(warm),
      retained_heap_bytes_median: retained.sort.fetch(TRIALS / 2) }
  end

  def samples(scope)
    Array.new(TRIALS) { paired_sample(scope) }.transpose
  end

  def paired_sample(scope)
    ArchUnit.clear_graph_cache
    before = heap_bytes
    cold = measure { verify(scope) }
    retained = heap_bytes - before
    warm = measure { verify(scope) }
    [cold, warm, retained]
  end

  def verify(scope)
    result = scope.selection
    return if result.status == :complete && result.matches.length == FILES - 1

    raise 'declaration selection did not match the fixture oracle'
  end

  def measure
    GC.start
    before = GC.stat(:total_allocated_objects)
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
    milliseconds = 1000 * (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start)
    { milliseconds: milliseconds.round(2), allocations: GC.stat(:total_allocated_objects) - before }
  end

  def heap_bytes
    GC.start
    ObjectSpace.memsize_of_all
  end

  def median(samples)
    samples.first.keys.to_h do |metric|
      [metric, samples.map { |sample| sample.fetch(metric) }.sort.fetch(TRIALS / 2)]
    end
  end
end

DeclarationSelectionStudy.run
