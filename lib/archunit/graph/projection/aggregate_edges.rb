# frozen_string_literal: true

require_relative 'report_labels'
require_relative 'graph_report_edge'

module ArchUnit
  module GraphReporting
    module Projection
      # Aggregates selected raw edges after applying one node-collapse strategy.
      module AggregateEdges
        module_function

        def aggregate(edges, labels, options)
          groups = Hash.new do |hash, key|
            hash[key] = { count: 0, external: false, import_kinds: [], evidence: [] }
          end

          edges.each do |edge|
            source = labels.fetch(edge.source)
            target = labels.fetch(ReportLabels.target(edge))
            next if !options.include_self_dependencies && source == target

            accumulate(groups[[source, target]], edge)
          end

          build_edges(groups)
        end

        def accumulate(group, edge)
          group[:count] += 1
          group[:external] ||= edge.external
          group[:import_kinds] |= edge.import_kinds
          group[:evidence] |= edge.evidence
        end
        private_class_method :accumulate

        def build_edges(groups)
          groups.sort_by { |(source, target), _group| [source, target] }.map do |key, group|
            GraphReportEdge.new(
              source: key.first, target: key.last, count: group[:count],
              external: group[:external], import_kinds: group[:import_kinds],
              evidence: group[:evidence]
            )
          end.freeze
        end
        private_class_method :build_edges
      end
    end
  end
end
