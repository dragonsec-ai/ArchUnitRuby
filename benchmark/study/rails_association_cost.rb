# frozen_string_literal: true

require 'archunit'
require 'tmpdir'
require_relative 'fixture'
require_relative 'rule_samples'

module PerformanceStudy
  # Paired trials over an identical, source-only Rails-shaped fixture, with an edge oracle.
  module RailsAssociationCost
    def self.run(pairs:, trials:)
      Dir.mktmpdir('archunit-association-cost') do |root|
        fixture = Fixture.new(root:, pairs:, density: 1, shape: 'rails')
        prepare(fixture)
        Array.new(trials) do |index|
          modes = index.even? ? [false, true] : [true, false]
          modes.map { |enabled| sample(fixture, enabled) }
        end
      ensure
        ArchUnit.clear_graph_cache
      end
    end

    def self.prepare(fixture)
      fixture.prepare
      fixture.pairs.times do |index|
        source = File.join(fixture.root, fixture.api(index))
        File.write(source, <<~RUBY)
          class Request#{index} < ApplicationRecord
            belongs_to :store, class_name: '::Db::Store#{index}'
          end
          raise 'do not execute target source'
        RUBY
      end
    end

    def self.sample(fixture, enabled)
      ArchUnit.clear_graph_cache
      before = RuleSamples.heap
      options = ArchUnit::CheckOptions.new(rails_associations: enabled)
      cold, graph = RuleSamples.measure { extract(fixture, options) }
      retained = RuleSamples.heap
      warm, cached = RuleSamples.measure { extract(fixture, options) }
      raise 'expected snapshot reuse' unless graph.equal?(cached)

      verify(fixture, graph, enabled)
      { enabled:, cold:, warm:, before:, retained: }
    end

    def self.extract(fixture, options)
      ArchUnit::Extraction.extract_graph(fixture.root, options:)
    end

    def self.verify(fixture, graph, enabled)
      actual = graph.reject { |edge| edge.source == edge.target }
      expected = enabled ? fixture.oracle.sort : []
      pairs = actual.map { |edge| [edge.source, edge.target] }.sort
      raise 'unexpected association graph' unless pairs == expected
      return if actual.all? { |edge| edge.import_kinds == [:rails_association] }

      raise 'invalid association evidence kind'
    end
    private_class_method :prepare, :sample, :extract, :verify
  end
end

if $PROGRAM_NAME == __FILE__
  pairs = 1000
  trials = 5
  runs = PerformanceStudy::RailsAssociationCost.run(pairs:, trials:)
  runtime = { ruby: RUBY_VERSION, platform: RUBY_PLATFORM }
  report = { runtime:, pairs:, trials:, samples: runs }
  output = ARGV.first
  if output
    File.write(output, JSON.pretty_generate(report))
    puts "Validated #{trials} pairs with #{pairs * 2} source files each; evidence: #{output}"
  else
    puts JSON.pretty_generate(report)
  end
end
