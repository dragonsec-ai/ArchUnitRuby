# frozen_string_literal: true

require 'archunit'
require 'tmpdir'
require_relative 'fixture'
require_relative 'rule_policies'
require_relative 'rule_samples'

module PerformanceStudy
  # One workload per fresh child when paired against a baseline checkout.
  module RuleSuite
    module_function

    def run(pairs: 1000, workload: 'varied')
      Dir.mktmpdir('archunit-rule-suite') do |root|
        fixture = Fixture.new(root:, pairs:, density: 1, shape: 'engines')
        fixture.prepare
        options = ArchUnit::CheckOptions.new(dependency_analysis: :imports_and_constants)
        rules = workload == 'graph' ? [] : RulePolicies.build(root, workload)
        measurements = stages(fixture, rules, options)
        measurements.merge(workload:, files: pairs * 2, rule_count: rules.length)
      ensure
        ArchUnit.clear_graph_cache
      end
    end

    def stages(fixture, rules, options)
      ArchUnit.clear_graph_cache
      before = RuleSamples.heap
      graph = graph_stage(fixture, options)
      suite = suite_stage(fixture, rules, options)
      RulePolicies.validate_controls(fixture, options)
      graph.merge(suite).merge(
        retained_before: before, controls: { forbidden: fixture.oracle.length, empty: 1 }
      )
    end

    def graph_stage(fixture, options)
      cold_graph, graph = RuleSamples.measure do
        ArchUnit::Extraction.extract_graph(fixture.root, options:)
      end
      sources = graph.select { |edge| edge.source == edge.target }.map(&:source)
      raise 'source inventory changed' unless sources.length == fixture.pairs * 2

      { cold_graph:, graph_sha256: RuleSamples.graph_digest(graph),
        retained_graph: RuleSamples.heap }
    end

    def suite_stage(fixture, rules, options)
      ArchUnit.clear_graph_cache
      RuleSamples.heap
      cold_plus_suite, = RuleSamples.measure do
        ArchUnit::Extraction.extract_graph(fixture.root, options:) if rules.empty?
        rules.each { |rule| raise 'cold suite failed' unless rule.check(options).empty? }
      end
      retained_suite = RuleSamples.heap
      warm_rules = rules.map { |rule| RuleSamples.check(rule, options) }
      { cold_plus_suite:, retained_suite:, warm_rules: }
    end

    def write(output, **settings)
      result = run(**settings)
      runtime = { ruby: RUBY_VERSION, platform: RUBY_PLATFORM, candidate_version: ArchUnit::VERSION,
                  revision: ENV.fetch('STUDY_REVISION', nil) }
      FileUtils.mkdir_p(File.dirname(output))
      File.write(output, JSON.pretty_generate(schema_version: 1, runtime:, result:))
      puts "Validated #{result[:workload]}: #{result[:files]} sources, #{result[:rule_count]} rules"
    end
  end
end

if $PROGRAM_NAME == __FILE__
  workload, output = ARGV
  unless ARGV.length == 2
    raise ArgumentError, 'usage: rule_suite.rb graph|one|identical|varied output.json'
  end

  pairs = Integer(ENV.fetch('STUDY_PAIRS', '1000'))
  PerformanceStudy::RuleSuite.write(output, pairs:, workload:)
end
