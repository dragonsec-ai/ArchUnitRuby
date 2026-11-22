# frozen_string_literal: true

require 'pathname'
require 'prism'
require_relative 'static_path_policy'

module ArchUnit
  module Extraction
    # Folds a small AST whitelist; never invokes methods/receivers from project source.
    class StaticImportPath
      MAX_DEPTH = 12
      MAX_BYTES = 16_384
      private_constant :MAX_DEPTH, :MAX_BYTES

      def initialize(source_path:, syntax_tree:)
        @source_path = source_path&.to_s
        @syntax_tree = syntax_tree
      end

      def resolve(node, depth = 0)
        return unless node && @source_path && depth <= MAX_DEPTH

        value = resolve_node(node, depth)
        value if valid_value?(value)
      rescue ArgumentError, Encoding::CompatibilityError
        nil
      end

      private

      def resolve_node(node, depth)
        case node
        when Prism::StringNode then node.unescaped
        when Prism::SourceFileNode then @source_path
        when Prism::CallNode then resolve_call(node, depth)
        end
      end

      def valid_value?(value)
        value.is_a?(String) && value.bytesize <= MAX_BYTES && !value.include?("\0")
      end

      def policy
        @policy ||= StaticPathPolicy.new(@syntax_tree)
      end

      def resolve_call(node, depth)
        return if node.block || node.safe_navigation?

        arguments = node.arguments&.arguments || []
        return directory(node, arguments) if node.name == :__dir__
        return concatenate(node, arguments, depth) if node.name == :+

        resolve_file_call(node, arguments, depth)
      end

      def resolve_file_call(node, arguments, depth)
        return unless file_receiver?(node.receiver) && policy.file_calls

        values = arguments.map { |argument| resolve(argument, depth + 1) }
        return if values.any?(&:nil?)

        file_call(node.name, values)
      end

      def directory(node, arguments)
        return unless node.receiver.nil? && arguments.empty? && policy.directory_calls

        @directory ||= File.dirname(File.realpath(@source_path))
      end

      def concatenate(node, arguments, depth)
        return unless arguments.length == 1 && policy.string_addition

        left = resolve(node.receiver, depth + 1)
        right = resolve(arguments.first, depth + 1)
        "#{left}#{right}" if left && right
      end

      def file_receiver?(node)
        return node.name == :File if node.is_a?(Prism::ConstantReadNode)

        node.is_a?(Prism::ConstantPathNode) && node.parent.nil? && node.name == :File
      end

      def file_call(name, values)
        case name
        when :dirname
          File.dirname(values.first) if values.length == 1 && absolute?(values.first)
        when :expand_path
          expand_path(values)
        end
      end

      def expand_path(values)
        return unless [1, 2].include?(values.length)
        return unless values.all? { |value| deterministic?(value) }
        return unless absolute?(values.length == 2 ? values.last : values.first)

        File.expand_path(*values)
      end

      def absolute?(value)
        Pathname.new(value).absolute?
      end

      def deterministic?(value)
        !value.start_with?('~') && !value.match?(%r{\A[a-z]:(?![/\\])}i)
      end
    end
    private_constant :StaticImportPath
  end
end
