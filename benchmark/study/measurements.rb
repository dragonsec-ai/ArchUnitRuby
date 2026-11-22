# frozen_string_literal: true

require 'objspace'

module PerformanceStudy
  # Timings are accepted only after the expected policy result has been verified.
  module Measurements
    def self.clock
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def self.sample(adapter, stage, expected)
      started = clock
      result = adapter.public_send(stage)
      seconds = clock - started
      unless result.length == expected
        raise "expected #{expected} diagnostics, got #{result.length}"
      end

      { seconds:, violations: result.length, ruby_heap_bytes: ObjectSpace.memsize_of_all }
    end

    def self.trial(tool, fixture, policy)
      before = prepare_trial(fixture)
      adapter = Adapters.build(tool, fixture.root, policy)
      expected = policy == 'forbidden' ? fixture.oracle.length : 0
      result = initial_samples(adapter, expected)
      result[:after_change] = changed_sample(adapter, fixture, policy)
      result.merge(ruby_heap_growth_bytes: result[:cold][:ruby_heap_bytes] - before)
    ensure
      fixture.write_api(0)
      ArchUnit.clear_graph_cache
    end

    def self.prepare_trial(fixture)
      fixture.write_api(0)
      ArchUnit.clear_graph_cache
      GC.start
      ObjectSpace.memsize_of_all
    end

    def self.changed_sample(adapter, fixture, policy)
      fixture.write_api(0, extra: true)
      expected = policy == 'forbidden' ? fixture.oracle(extra: true).length : 0
      sample(adapter, :cold, expected)
    end

    def self.initial_samples(adapter, expected)
      { cold: sample(adapter, :cold, expected), warm: sample(adapter, :warm, expected) }
    end

    def self.summarize(samples)
      values = samples.sort
      middle = values.length / 2
      median = values.length.odd? ? values[middle] : (values[middle - 1] + values[middle]) / 2.0
      { median_seconds: median, samples_seconds: samples }
    end

    def self.peak_rss_kb
      return unless File.file?('/proc/self/status')

      File.read('/proc/self/status')[/^VmHWM:\s+(\d+)/, 1]&.to_i
    end
  end
end
