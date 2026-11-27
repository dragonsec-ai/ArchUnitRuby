# frozen_string_literal: true

require_relative 'collapse_node'

module ArchUnit
  module GraphReporting
    module Projection
      # Keep raw node identity through traversal. Disambiguate only colliding display labels,
      # after collapse, so every renderer can link to the right node without changing its format.
      # @api private
      module ReportLabels
        External = Data.define(:label)

        module_function

        def target(edge)
          edge.external ? External.new(edge.target) : edge.target
        end

        def name(node)
          node.is_a?(External) ? node.label : node
        end

        def build(nodes, collapse)
          labels = nodes.to_h { |node| [node, CollapseNode.collapse(name(node), collapse)] }
          external, internal = labels.partition { |node, _label| node.is_a?(External) }
          return labels if external.empty?

          aliases = external_aliases(external.map(&:last), internal.map(&:last))
          external.each { |node, label| labels[node] = aliases.fetch(label, label) }
          labels
        end

        def external_aliases(external, internal)
          reserved = (external + internal).to_set
          (external & internal).sort.to_h do |original|
            label = original
            label = "#{label} [external]" until reserved.add?(label)
            [original, label]
          end
        end
        private_class_method :external_aliases
      end
    end
  end
end
