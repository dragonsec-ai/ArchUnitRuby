# frozen_string_literal: true

require 'json'
require 'tmpdir'
require 'archunit'
require_relative 'fixture'
require_relative 'adapters'
require_relative 'measurements'
require_relative 'startup_samples'
require_relative '../semantic/comparator'

module PerformanceStudy
  # Repeated, alternating, oracle-checked trials; no machine-speed threshold or leaderboard.
  module Runner
    module_function

    def run(pairs: 100, trials: 5, compare: false, startup: true)
      raise ArgumentError, 'trials must be between 1 and 9' unless (1..9).cover?(trials)

      SemanticStudy::Comparator.load if compare
      cases(pairs).map { |settings| measure_case(settings, trials, compare:, startup:) }
    end

    def cases(pairs)
      %w[rails engines].product([1, 3], %w[allowed forbidden]).map do |shape, density, policy|
        { shape:, density:, pairs:, policy: }
      end
    end

    def measure_case(settings, trials, compare:, startup:)
      Dir.mktmpdir('archunit-performance-study') do |root|
        fixture = Fixture.new(root:, **settings.except(:policy))
        fixture.prepare
        tools = compare ? %w[archunit archspec] : ['archunit']
        samples = repeated_trials(tools, fixture, settings[:policy], trials)
        starts = startup_samples(tools, fixture, settings[:policy], trials) if startup
        settings.merge(files: fixture.pairs * 2, trials:, samples:, startup: starts,
                       summary: summary(samples))
      end
    end

    def repeated_trials(tools, fixture, policy, trials)
      samples = tools.to_h { |tool| [tool, []] }
      trials.times do |index|
        order = index.even? ? tools : tools.reverse
        order.each { |tool| samples[tool] << Measurements.trial(tool, fixture, policy) }
      end
      samples
    end

    def startup_samples(tools, fixture, policy, trials)
      samples = tools.to_h { |tool| [tool, []] }
      trials.times do |index|
        order = index.even? ? tools : tools.reverse
        order.each { |tool| samples[tool] << StartupSamples.run(tool, fixture, policy) }
      end
      samples
    end

    def summary(samples)
      samples.transform_values do |trials|
        %i[cold warm after_change].to_h do |stage|
          [stage, Measurements.summarize(trials.map { |trial| trial[stage][:seconds] })]
        end
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  compare = ARGV.delete('--archspec')
  output = ARGV.shift || 'pkg/performance-study.json'
  raise ArgumentError, 'usage: run.rb [--archspec] [output.json]' unless ARGV.empty?

  trials = Integer(ENV.fetch('STUDY_TRIALS', '5'))
  pairs = Integer(ENV.fetch('STUDY_PAIRS', '100'))
  results = PerformanceStudy::Runner.run(pairs:, trials:, compare:)
  gems = %w[archunit archspec rubydex prism json csv].to_h do |name|
    [name, Gem.loaded_specs[name]&.version&.to_s]
  end
  runtime = { ruby: RUBY_VERSION, platform: RUBY_PLATFORM, candidate_version: ArchUnit::VERSION,
              revision: ENV.fetch('GITHUB_SHA', nil), gems: }
  FileUtils.mkdir_p(File.dirname(output))
  File.write(output, JSON.pretty_generate(schema_version: 1, runtime:, cases: results))
  puts "Validated #{results.length} performance shapes/policies; evidence: #{output}"
end
