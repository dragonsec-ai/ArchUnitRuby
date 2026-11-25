# frozen_string_literal: true

require 'digest'
require 'json'
require_relative 'measurements'

module PerformanceStudy
  # Same-process cold/warm stages; keep GC outside the timed operations.
  module RuleSamples
    module_function

    def measure
      started_objects = GC.stat(:total_allocated_objects)
      started = Measurements.clock
      value = yield
      seconds = Measurements.clock - started
      [{ seconds:, allocated_objects: GC.stat(:total_allocated_objects) - started_objects }, value]
    end

    def heap
      GC.start
      { ruby_heap_bytes: ObjectSpace.memsize_of_all, peak_rss_kb: Measurements.peak_rss_kb }
    end

    def check(rule, options)
      sample, violations = measure { rule.check(options) }
      raise 'passing suite produced violations' unless violations.empty?

      sample
    end

    def graph_digest(graph)
      edges = graph.map do |edge|
        edge.to_h.merge(evidence: edge.evidence.map(&:to_h))
      end
      Digest::SHA256.hexdigest(JSON.generate(edges))
    end
  end
end
