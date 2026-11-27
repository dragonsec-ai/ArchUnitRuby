# frozen_string_literal: true

require 'prism'

module ArchUnit
  module Extraction
    # Converts a literal Prism constant path to a name without following dynamic receivers.
    module StaticConstantName
      private

      def static_name(node)
        return node.name.to_s if node.is_a?(Prism::ConstantReadNode)
        return unless node.is_a?(Prism::ConstantPathNode)
        return "::#{node.name}" if node.parent.nil?

        parent = static_name(node.parent)
        "#{parent}::#{node.name}" if parent
      end
    end
    private_constant :StaticConstantName
  end
end
