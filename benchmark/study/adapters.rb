# frozen_string_literal: true

module PerformanceStudy
  # Public rule/extraction calls only; neither adapter evaluates the fixture project.
  module Adapters
    # Current expanded-file graph and ordinary fluent rule execution.
    class Candidate
      def initialize(root, policy)
        mood = ArchUnit.project_files(root).in_path('**/app/api/**')
        mood = policy == 'forbidden' ? mood.should_not : mood.should
        @rule = mood.depend_on_files.in_path('**/app/db/**')
        @options = ArchUnit::CheckOptions.new(dependency_analysis: :imports_and_constants)
      end

      def cold
        ArchUnit.clear_graph_cache
        warm
      end

      def warm
        @rule.check(@options)
      end
    end

    # Published comparator with explicit in-memory graph reuse for warm evaluation.
    class Comparator
      def initialize(root, policy)
        @root = root
        @definition = ArchSpec.define do
          source '**/*.rb'
          component :api, in: '**/app/api/**/*.rb'
          component :db, in: '**/app/db/**/*.rb'
          policy == 'forbidden' ? api.cannot_use(:db) : api.can_only_use(:db)
        end
      end

      def cold
        @graph = ArchSpec::Analyzer.analyze(@definition, root: @root)
        warm
      end

      def warm
        ArchSpec::Evaluator.evaluate(@definition, @graph)
      end
    end

    def self.build(name, root, policy)
      type = name == 'archunit' ? Candidate : Comparator
      type.new(root, policy)
    end
  end
end
