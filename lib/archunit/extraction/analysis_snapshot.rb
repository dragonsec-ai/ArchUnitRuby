# frozen_string_literal: true

module ArchUnit
  module Extraction
    # Immutable facts about one analysis, not a claim of semantic completeness.
    # @api private
    module AnalysisSnapshot
      COUNTERS = %i[
        source_files imports unresolved_imports unresolved_constant_references
        ambiguous_constant_references
      ].freeze
      ASSOCIATION_COUNTERS = %i[
        rails_association_sites unresolved_rails_associations ambiguous_rails_associations
      ].freeze
      private_constant :COUNTERS, :ASSOCIATION_COUNTERS

      def self.graph(root, patterns, options, counters: nil, status: 'analyzed')
        settings = {
          kind: 'dependency_graph', dependency_analysis: options.dependency_analysis.to_s.freeze,
          rails_imports: options.rails_imports, load_paths: options.load_paths
        }
        settings[:rails_associations] = true if options.rails_associations?
        build(root, patterns, settings, graph_counters(options, counters), status)
      end

      def self.source(discovery, count: nil, status: 'analyzed')
        settings = {
          kind: 'source_metrics', dependency_analysis: nil, rails_imports: nil, load_paths: nil
        }
        counters = COUNTERS.to_h { |key| [key, key == :source_files ? count : nil] }
        build(discovery.root, discovery.patterns, settings, counters, status)
      end

      def self.graph_counters(options, values)
        keys = options.rails_associations? ? COUNTERS + ASSOCIATION_COUNTERS : COUNTERS
        counters = keys.to_h { |key| [key, values&.fetch(key)] }
        unless options.constant_references?
          counters[:unresolved_constant_references] = nil
          counters[:ambiguous_constant_references] = nil
        end
        counters
      end
      private_class_method :graph_counters

      def self.build(root, patterns, settings, counters, status)
        {
          project_root: root.to_s.tr('\\', '/').freeze,
          effective_source_exclusions: patterns.sort.freeze,
          status:, counters: counters.freeze, **settings
        }.freeze
      end
      private_class_method :build
    end
    private_constant :AnalysisSnapshot
  end
end
