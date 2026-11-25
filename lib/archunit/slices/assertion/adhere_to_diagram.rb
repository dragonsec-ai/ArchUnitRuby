# frozen_string_literal: true

require_relative '../../common/projection/projected_edge'
require_relative '../uml/plant_uml_diagram'
require_relative 'diagram_adherence_options'
require_relative 'slice_dependency_violation'

module ArchUnit
  module Slices
    # Pure assertions over projected slice dependencies.
    module Assertion
      module_function

      def gather_diagram_adherence_violations(edges, diagram, options = nil)
        validate_diagram_arguments(edges, diagram, options)
        options ||= DiagramAdherenceOptions.new

        edges.filter_map do |projected|
          edge = visible_dependency(projected, options)
          next unless edge
          next if ignored_orphan?(edge, diagram, options)
          next if diagram.allows?(edge.source_label, edge.target_label)

          diagram_violation(edge)
        end
      end

      def diagram_violation(edge)
        SliceDependencyViolation.new(
          dependency: edge, source_slice: edge.source_label,
          target_slice: edge.target_label, rule: :adhere_to_diagram, is_negated: false
        )
      end
      private_class_method :diagram_violation

      def ignored_orphan?(edge, diagram, options)
        return false unless options.ignore_orphan_slices?

        !diagram.components.include?(edge.source_label) ||
          !diagram.components.include?(edge.target_label)
      end
      private_class_method :ignored_orphan?

      def visible_dependency(edge, options)
        return edge unless options.ignore_external_slices? && edge.cumulated_edges.any?(&:external)

        internal = edge.cumulated_edges.reject(&:external)
        edge.with(cumulated_edges: internal) unless internal.empty?
      end
      private_class_method :visible_dependency

      def validate_diagram_arguments(edges, diagram, options)
        unless edges.is_a?(Array) && edges.all?(Common::Projection::ProjectedEdge)
          raise ArgumentError, 'edges must be an Array of ProjectedEdge values'
        end
        unless diagram.is_a?(Uml::PlantUmlDiagram)
          raise ArgumentError, 'diagram must be a PlantUmlDiagram'
        end
        return if options.nil? || options.is_a?(DiagramAdherenceOptions)

        raise ArgumentError, 'options must be DiagramAdherenceOptions or nil'
      end
      private_class_method :validate_diagram_arguments
    end
  end
end
