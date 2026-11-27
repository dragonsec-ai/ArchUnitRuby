# frozen_string_literal: true

require_relative '../static_constant_name'

module ArchUnit
  module Extraction
    module Declarations
      # Records a possible alias or rebinding without trying to read the assigned value.
      module ConstantAssignment
        extend StaticConstantName

        BARE = %i[
          constant_write_node constant_and_write_node constant_or_write_node
          constant_operator_write_node constant_target_node
        ].freeze
        PATH = %i[
          constant_path_write_node constant_path_and_write_node constant_path_or_write_node
          constant_path_operator_write_node
        ].freeze
        private_constant :BARE, :PATH

        def self.written_name(node)
          return node.name.to_s if BARE.include?(node.type)
          return static_name(node.target) if PATH.include?(node.type)
          return unless node.type == :constant_path_target_node

          parent = node.parent ? static_name(node.parent) : ''
          "#{parent}::#{node.name}" if parent
        end
      end
      private_constant :ConstantAssignment
    end
  end
end
