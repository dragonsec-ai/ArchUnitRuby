# frozen_string_literal: true

require_relative '../../common/extraction/graph'
require_relative 'aggregate_edges'
require_relative 'graph_query_options'
require_relative 'graph_report_snapshot'
require_relative 'node_selection'

module ArchUnit
  module GraphReporting
    module Projection
      DEFAULT_TITLE = 'ArchUnitRuby Dependency Graph'

      # Builds the one immutable representation consumed by every graph renderer.
      class SnapshotFactory
        class << self
          def create(graph, options = nil)
            validate_graph(graph)
            options = GraphQueryOptions.resolve(options)
            query_edges = external_query_edges(graph, options)
            selected_nodes = NodeSelection.select(query_edges, options)
            raw_edges = selected_edges(query_edges, selected_nodes, options)
            labels = ReportLabels.build(selected_nodes, options.collapse)
            report_edges = AggregateEdges.aggregate(raw_edges, labels, options)
            report_nodes = build_nodes(labels)

            build_snapshot(options, report_nodes, report_edges, raw_edges)
          end

          private

          def validate_graph(value)
            return if value.is_a?(Common::Extraction::Graph)

            raise ArgumentError, 'graph must be a Graph value'
          end

          def external_query_edges(graph, options)
            return graph.to_a if options.include_external_dependencies

            graph.reject(&:external)
          end

          def selected_edges(edges, selected_nodes, options)
            edges.select do |edge|
              (options.include_self_dependencies || !edge.self_dependency?) &&
                selected_nodes.include?(edge.source) &&
                selected_nodes.include?(ReportLabels.target(edge))
            end
          end

          def build_nodes(labels)
            labels.values.uniq.sort.each_with_index.map do |label, index|
              GraphReportNode.new(id: "n#{index}", label:)
            end.freeze
          end

          def build_snapshot(options, nodes, edges, raw_edges)
            GraphReportSnapshot.new(
              title: options.title || DEFAULT_TITLE,
              nodes:, edges:,
              summary: GraphReportSummary.new(
                node_count: nodes.length, edge_count: edges.length,
                raw_edge_count: raw_edges.length,
                external_edge_count: raw_edges.count(&:external)
              )
            )
          end
        end

        private_class_method :new
      end
    end
  end
end
