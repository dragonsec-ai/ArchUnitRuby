# frozen_string_literal: true

require_relative '../common/projection/project_to_nodes'
require_relative '../common/projection/project_edges'
require_relative '../common/projection/edge_projections'

module ArchUnit
  module Extraction
    # Three lazy immutable views owned solely by one cached analysis entry.
    # No graph-keyed global map or caller-supplied mapper is memoized.
    # @api private
    class GraphViews
      attr_reader :graph

      def initialize(graph)
        @graph = graph
        @values = {}
        @mutex = Mutex.new
        freeze
      end

      def nodes
        fetch(:nodes) { Common::Projection.project_to_nodes(graph) }
      end

      def internal_edges
        fetch(:internal_edges) do
          Common::Projection.project_edges(graph, Common::Projection.per_internal_edge)
        end
      end

      def external_edges
        fetch(:external_edges) do
          Common::Projection.project_edges(graph, Common::Projection.per_external_edge)
        end
      end

      private

      def fetch(key)
        @mutex.synchronize { @values.fetch(key) { @values[key] = yield } }
      end
    end
    private_constant :GraphViews
  end
end
