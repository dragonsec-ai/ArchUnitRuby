# frozen_string_literal: true

require 'prism'

module ArchUnit
  module Extraction
    # Bounds Kernel.load arguments without evaluating paths, wrapping, or block conversion.
    module LoadArguments
      VARIADIC = [Prism::SplatNode, Prism::ForwardingArgumentsNode].freeze
      PURE_WRAP = [Prism::TrueNode, Prism::FalseNode, Prism::NilNode,
                   Prism::LocalVariableReadNode].freeze
      private_constant :VARIADIC, :PURE_WRAP

      def self.possible?(arguments)
        !arguments.empty? && arguments.count { |argument| !variadic?(argument) } <= 2
      end

      def self.path(arguments)
        arguments.first unless arguments.any? { |argument| variadic?(argument) }
      end

      def self.effectful?(node, arguments)
        node.block.is_a?(Prism::BlockArgumentNode) ||
          (arguments.length > 1 && PURE_WRAP.none? { |type| arguments[1].is_a?(type) })
      end

      def self.variadic?(argument)
        VARIADIC.any? { |type| argument.is_a?(type) }
      end
      private_class_method :variadic?
    end
    private_constant :LoadArguments
  end
end
