# frozen_string_literal: true

require_relative '../common/extraction/edge'
require_relative '../common/extraction/graph'
require_relative 'extraction_profile'

module ArchUnit
  module Extraction
    # Final graph construction shared with the counted extraction pipeline.
    # @api private
    module GraphAssembly
      def self.build(edges, profile)
        merged = ExtractionProfile.measure(profile, :edge_merge) { merge_parallel_edges(edges) }
        profile&.increment(:merged_edges, merged.length)
        Common::Extraction::Graph.new(merged)
      end

      def self.merge_parallel_edges(edges)
        edges.group_by { |edge| [edge.source, edge.target] }.values.map do |parallel_edges|
          first = parallel_edges.first
          Common::Extraction::Edge.new(
            source: first.source, target: first.target, external: first.external,
            import_kinds: parallel_edges.flat_map(&:import_kinds),
            evidence: parallel_edges.flat_map(&:evidence)
          )
        end
      end
      private_class_method :merge_parallel_edges
    end
    private_constant :GraphAssembly
  end
end
