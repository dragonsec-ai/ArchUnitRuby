# frozen_string_literal: true

require 'archunit'
require 'fileutils'
require 'json'
require 'objspace'
require 'open3'
require_relative 'measurements'

module PerformanceStudy
  # Pinned production-source study, not an upstream architecture/security judgment.
  module RealProject
    def self.run(root, trials: 3, expected_sources: 2510)
      before = prepare_root(root)
      results = %i[imports imports_and_constants].map do |mode|
        samples = Array.new(trials) { profile(root, mode, expected_sources) }
        seconds = samples.map { |item| item[:cold_seconds] }
        { mode:, samples:, summary: Measurements.summarize(seconds) }
      end
      raise 'target checkout changed during analysis' unless before == git_status(root)

      results
    ensure
      ArchUnit.clear_graph_cache
    end

    def self.prepare_root(root)
      verify_revision(root)
      before = git_status(root)
      raise 'pinned checkout must start clean' unless before.empty?

      before
    end

    def self.verify_revision(root)
      output, errors, status = Open3.capture3('git', '-C', root, 'rev-parse', 'HEAD')
      expected = '2de9c9be4f89e392fe500dd27f928d6b1184bf09'
      return if status.success? && output.strip == expected

      raise "wrong pinned revision: #{output}#{errors}"
    end

    def self.profile(root, mode, expected_sources)
      graph, cold, options = cold_profile(root, mode, expected_sources)
      warm = warm_profile(root, options, graph)
      { cold_seconds: cold.stage_seconds[:total], warm_seconds: warm.stage_seconds[:total],
        graph_edges: graph.length, counters: cold.counters,
        ruby_heap_bytes: ObjectSpace.memsize_of_all,
        process_lifetime_peak_rss_kb: Measurements.peak_rss_kb }
    end

    def self.cold_profile(root, mode, expected_sources)
      ArchUnit.clear_graph_cache
      GC.start
      options = ArchUnit::CheckOptions.new(dependency_analysis: mode)
      cold = ArchUnit::Extraction::ExtractionProfile.new
      graph = ArchUnit::Extraction.extract_graph(root, options:, profile: cold)
      unless cold.counters[:source_files] == expected_sources
        raise 'pinned source scope changed; review, do not auto-bless it'
      end

      [graph, cold, options]
    end

    def self.warm_profile(root, options, graph)
      warm = ArchUnit::Extraction::ExtractionProfile.new
      cached = ArchUnit::Extraction.extract_graph(root, options:, profile: warm)
      raise 'warm graph not reused' unless cached.equal?(graph) && warm.cache_hit?
      raise 'warm graph repeats cold work' unless warm.counters.values.all?(&:zero?)

      warm
    end

    def self.git_status(root)
      output, errors, status = Open3.capture3(
        { 'GIT_OPTIONAL_LOCKS' => '0' }, 'git', '-C', root, 'status', '--porcelain'
      )
      raise "could not verify checkout: #{errors}" unless status.success?

      output
    end
  end
end

if $PROGRAM_NAME == __FILE__
  root, output = ARGV
  unless root && output && ARGV.length == 2
    raise ArgumentError,
          'usage: real_project.rb ROOT OUTPUT.json'
  end

  results = PerformanceStudy::RealProject.run(root)
  payload = { ruby: RUBY_VERSION, platform: RUBY_PLATFORM, candidate_version: ArchUnit::VERSION,
              revision: ENV.fetch('GITHUB_SHA', nil),
              target_revision: '2de9c9be4f89e392fe500dd27f928d6b1184bf09',
              limitations: 'Sparse source; no target boot or semantic-completeness claim',
              cases: results }
  FileUtils.mkdir_p(File.dirname(output))
  File.write(output, JSON.pretty_generate(payload))
  puts "Read-only Discourse profiling passed in both modes; evidence: #{output}"
end
