# frozen_string_literal: true

require 'prism'
require_relative '../common/extraction/import_kind'
require_relative 'conservative_local_flow'
require_relative 'local_string_tracker'
require_relative 'load_arguments'
require_relative 'static_import_path'
require_relative 'import_calls'

module ArchUnit
  module Extraction
    # Collects supported dependency calls from a Prism syntax tree.
    class ImportVisitor < Prism::Visitor
      include ConservativeLocalFlow

      attr_reader :imports, :unresolved_imports

      def initialize(source_path: nil, syntax_tree: nil, rails_imports: false)
        super()
        @imports = []
        @unresolved_imports = 0
        policy = ImportSourcePolicy.new(syntax_tree)
        @calls = ImportCalls.new(rails_imports:, source_policy: policy)
        @local_strings = LocalStringTracker.new(
          path_resolver: StaticImportPath.new(source_path:, source_policy: policy)
        )
      end

      def visit_call_node(node)
        import_kind = @calls.kind(node)
        record_import(node, import_kind) if import_kind
        super
        invalidate_escaped_locals(node) unless import_kind
      end

      def visit_local_variable_write_node(node)
        super
        @local_strings.assign(node.name, node.value)
      end

      private

      def record_import(node, import_kind)
        arguments = node.arguments&.arguments || []
        module_name = import_module_name(node, arguments, import_kind)
        unless valid_module_name?(module_name)
          @unresolved_imports += 1
          return
        end

        @imports << located_import(module_name, import_kind, node)
      end

      def import_module_name(node, arguments, import_kind)
        invalidate_import_arguments(node, arguments, import_kind)
        @local_strings.resolve(@calls.path(arguments, import_kind))
      end

      def invalidate_import_arguments(node, arguments, kind)
        unsafe = @calls.uncertain?(kind) || unsafe_auxiliary_arguments?(node, arguments, kind)
        unsafe ||= kind == Common::Extraction::ImportKind::LOAD &&
                   LoadArguments.effectful?(node, arguments)
        @local_strings.invalidate_all if unsafe
      end

      def unsafe_auxiliary_arguments?(node, arguments, import_kind)
        return true if node.block.is_a?(Prism::BlockArgumentNode)
        return false unless import_kind == Common::Extraction::ImportKind::AUTOLOAD

        [Prism::SymbolNode, Prism::StringNode].none? { |type| arguments.first.is_a?(type) }
      end

      def located_import(module_name, import_kind, node)
        [module_name, import_kind, node.location.start_line, node.location.end_line]
      end

      def valid_module_name?(module_name)
        module_name.is_a?(String) && !module_name.empty? && !module_name.include?("\0")
      end

      def invalidate_escaped_locals(node)
        @local_strings.invalidate_escaped(node)
        @local_strings.capture_scopes if %i[eval binding local_variable_set].include?(node.name)
      end
    end
    private_constant :ImportVisitor
  end
end
