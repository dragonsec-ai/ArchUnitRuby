# frozen_string_literal: true

require 'prism'

module ArchUnit
  module Extraction
    # Source-local guards, not a claim to model arbitrary cross-file monkey-patching.
    class ImportSourcePolicy < Prism::Visitor
      REFLECTION = %i[
        eval class_eval module_eval instance_eval class_exec module_exec instance_exec
        define_method define_singleton_method alias_method remove_method undef_method
        const_set remove_const refine using send public_send __send__ singleton_class
      ].freeze
      private_constant :REFLECTION

      def initialize(tree)
        super()
        @tree = tree
        @disabled = {}
      end

      def allowed?(capability)
        unless @analyzed
          @analyzed = true
          visit(@tree)
        end
        !@disabled[capability]
      end

      def visit_constant_write_node(node)
        shadow(node.name)
        super
      end
      alias visit_constant_or_write_node visit_constant_write_node
      alias visit_constant_and_write_node visit_constant_write_node
      alias visit_constant_operator_write_node visit_constant_write_node

      def visit_constant_target_node(node)
        shadow(node.name)
        super
      end

      def visit_constant_path_target_node(node)
        shadow(node.name)
        super
      end

      def visit_constant_path_write_node(node)
        shadow(node.target.name)
        super
      end
      alias visit_constant_path_or_write_node visit_constant_path_write_node
      alias visit_constant_path_and_write_node visit_constant_path_write_node
      alias visit_constant_path_operator_write_node visit_constant_path_write_node

      def visit_class_node(node)
        shadow(node.constant_path.name) if node.constant_path.respond_to?(:name)
        super
      end

      def visit_module_node(node)
        shadow(node.constant_path.name) if node.constant_path.respond_to?(:name)
        super
      end

      def visit_def_node(node)
        @disabled[:directory_calls] = true if node.name == :__dir__
        @disabled[:string_addition] = true if node.name == :+
        @disabled[:rails_helpers] = true if node.name == :require_dependency
        shadow(node.receiver.name) if node.receiver.respond_to?(:name)
        super
      end

      def visit_singleton_class_node(node)
        shadow(node.expression.name) if node.expression.respond_to?(:name)
        super
      end

      def visit_call_node(node)
        disable if REFLECTION.include?(node.name)
        check_autoload(node) if node.name == :autoload
        check_mixin(node) if %i[include prepend extend].include?(node.name)
        super
      end

      def visit_alias_method_node(node)
        disable
        super
      end

      def visit_undef_node(node)
        disable
        super
      end

      private

      def shadow(name)
        @disabled[:file_calls] = true if name == :File
        @disabled[:string_addition] = true if name == :String
      end

      def check_autoload(node)
        name = node.arguments&.arguments&.first
        if name.is_a?(Prism::SymbolNode) || name.is_a?(Prism::StringNode)
          shadow(name.unescaped.to_sym)
        else
          disable
        end
      end

      def check_mixin(node)
        shadow(node.receiver.name) if node.receiver.respond_to?(:name)
      end

      def disable
        @disabled.merge!(file_calls: true, directory_calls: true,
                         string_addition: true, rails_helpers: true)
      end
    end
    private_constant :ImportSourcePolicy
  end
end
