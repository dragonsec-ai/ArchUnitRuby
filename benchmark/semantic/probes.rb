# frozen_string_literal: true

require 'archunit'
require 'fileutils'
require 'json'
require 'tmpdir'
require_relative 'syntax_facts'
require_relative 'comparator'

module SemanticStudy
  # Read-only analysis of generated production fixtures; no source/config/Gemfile execution.
  module Probes
    DB = 'module Db; class Store; def self.delete_all; end; def self.read; end; end; end'

    module_function

    def run(compare: false)
      Comparator.load if compare
      cases = JSON.parse(File.read(File.join(__dir__, 'cases.json')))
      cases.map { |specification| observe(specification, compare:) }
    end

    def observe(specification, compare:)
      Dir.mktmpdir('archunit-semantic-probe') do |root|
        prepare(root, specification)
        result = library_facts(root, specification)
        result[:archspec] = Comparator.facts(root, specification) if compare
        result
      ensure
        ArchUnit.clear_graph_cache
      end
    end

    def prepare(root, specification)
      fixture_files(specification).each do |name, source|
        file = File.join(root, name)
        FileUtils.mkdir_p(File.dirname(file))
        File.write(file, "#{source}\nraise 'must not execute target source'")
      end
    end

    def fixture_files(specification)
      files = {
        'Gemfile' => "raise 'must not execute target Gemfile'",
        'app/api/request.rb' => specification.fetch('source'), 'app/db/store.rb' => DB,
        'base.rb' => 'class Base; Store = ::Db::Store; end', 'alias.rb' => 'AliasDb = ::Db'
      }
      files['app/db/reopened.rb'] = specification['extra_source'] if specification['extra_source']
      files
    end

    def library_facts(root, specification)
      profile = ArchUnit::Extraction::ExtractionProfile.new
      options = ArchUnit::CheckOptions.new(dependency_analysis: :imports_and_constants)
      graph = ArchUnit::Extraction.extract_graph(root, options:, profile:)
      count = boundary_count(root, specification, options)
      { name: specification['name'], direct_file_boundary_violations: count,
        counters: profile.counters, syntax: syntax_facts(specification),
        metric_method_fields: ArchUnit::MetricMethodInfo.members,
        has_semantic_method_edges: graph.any? { |edge| edge.respond_to?(:resolved_method) } }
    end

    def boundary_count(root, specification, options)
      rule = ArchUnit.project_files(root).in_path('app/api/**')
                     .should_not.depend_on_files.in_path('app/db/**')
      count = rule.check(options).length
      unless count == specification['expected_direct_db']
        raise "unexpected direct dependency: #{specification['name']}"
      end

      count
    end

    def syntax_facts(specification)
      parsed = Prism.parse(specification.fetch('source'))
      raise 'invalid probe source' unless parsed.success?

      syntax = SyntaxFacts.new
      syntax.visit(parsed.value)
      { calls: syntax.calls, declarations: syntax.methods, superclasses: syntax.superclasses }
    end
  end
end

if $PROGRAM_NAME == __FILE__
  compare = ARGV.delete('--archspec')
  output = ARGV.shift
  raise ArgumentError, 'usage: probes.rb [--archspec] [output.json]' unless ARGV.empty?

  results = SemanticStudy::Probes.run(compare:)
  runtime = { ruby: RUBY_VERSION, platform: RUBY_PLATFORM, archunit: ArchUnit::VERSION,
              prism: Gem.loaded_specs.fetch('prism').version.to_s }
  payload = JSON.pretty_generate(runtime:, cases: results)
  output ? File.write(output, payload) : puts(payload)
end
