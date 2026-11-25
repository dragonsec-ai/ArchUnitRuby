# frozen_string_literal: true

require 'prism'

module ArchUnit
  module Extraction
    # Recognizes explicit literal keyword options, not arbitrary Ruby option expressions.
    module RailsAssociationOptions
      CLASS_NAME = /\A(?:::)?[A-Z]\w*(?:::[A-Z]\w*)*\z/
      private_constant :CLASS_NAME

      def self.explicit_literal(arguments)
        return unless supported_arguments?(arguments)

        options = keyword_options(arguments.last)
        return if options.nil? || indirect?(options)

        class_name_literal(options['class_name'])
      end

      def self.class_name_literal(value)
        return unless value.is_a?(Prism::StringNode) || value.is_a?(Prism::SymbolNode)

        name = value.unescaped
        value if name.ascii_only? && CLASS_NAME.match?(name)
      end

      def self.supported_arguments?(arguments)
        return false unless arguments.first.is_a?(Prism::SymbolNode)
        return false unless arguments.last.is_a?(Prism::KeywordHashNode)

        arguments.length == 2 ||
          (arguments.length == 3 && arguments[1].is_a?(Prism::LambdaNode))
      end

      def self.keyword_options(node)
        node.elements.each_with_object({}) do |entry, options|
          return nil unless entry.is_a?(Prism::AssocNode) && entry.key.is_a?(Prism::SymbolNode)

          key = entry.key.unescaped
          return nil if options.key?(key)

          options[key] = entry.value
        end
      end

      def self.indirect?(options)
        return true if %w[through as source_type anonymous_class].any? { |key| options.key?(key) }

        polymorphic = options['polymorphic']
        polymorphic && !polymorphic.is_a?(Prism::FalseNode) && !polymorphic.is_a?(Prism::NilNode)
      end
      private_class_method :supported_arguments?, :keyword_options, :class_name_literal, :indirect?
    end
    private_constant :RailsAssociationOptions
  end
end
