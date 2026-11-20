# frozen_string_literal: true

require 'prism'
require_relative '../common/extraction/import_kind'
require_relative 'conservative_local_flow'
require_relative 'local_string_tracker'
require_relative 'load_arguments'

module ArchUnit
  module Extraction
    # Collects supported dependency calls from a Prism syntax tree.
    class ImportVisitor < Prism::Visitor
      include ConservativeLocalFlow

      CALL_KINDS = {
        require: Common::Extraction::ImportKind::REQUIRE,
        require_relative: Common::Extraction::ImportKind::REQUIRE_RELATIVE,
        autoload: Common::Extraction::ImportKind::AUTOLOAD,
        load: Common::Extraction::ImportKind::LOAD
      }.freeze

      attr_reader :imports, :unresolved_imports

      def initialize
        super
        @imports = []
        @unresolved_imports = 0
        @local_strings = LocalStringTracker.new
      end

      def visit_call_node(node)
        import_call = supported_import_call?(node)
        record_import(node) if import_call
        super
        invalidate_escaped_locals(node) unless import_call
      end

      def visit_local_variable_write_node(node)
        super
        @local_strings.assign(node.name, node.value)
      end

      private

      def record_import(node)
        import_kind = CALL_KINDS[node.name]
        arguments = node.arguments&.arguments || []
        module_name = import_module_name(node, arguments, import_kind)
        unless valid_module_name?(module_name)
          @unresolved_imports += 1
          return
        end

        @imports << located_import(module_name, import_kind, node)
      end

      def import_module_name(node, arguments, import_kind)
        if import_kind == Common::Extraction::ImportKind::LOAD
          # Arguments are evaluated before the call: a wrap expression or & conversion can
          # mutate an earlier path object. Never reuse its pre-call tracked string value.
          @local_strings.invalidate_all if LoadArguments.effectful?(node, arguments)
          return @local_strings.resolve(LoadArguments.path(arguments))
        end

        @local_strings.resolve(import_argument(arguments, import_kind))
      end

      def located_import(module_name, import_kind, node)
        [module_name, import_kind, node.location.start_line, node.location.end_line]
      end

      def valid_module_name?(module_name)
        module_name.is_a?(String) && !module_name.empty? && !module_name.include?("\0")
      end

      def supported_import_call?(node)
        import_kind = CALL_KINDS[node.name]
        import_kind && supported_receiver?(node, import_kind) &&
          !import_argument(node.arguments&.arguments || [], import_kind).nil?
      end

      def supported_receiver?(node, import_kind)
        return true if node.receiver.nil?
        if import_kind == Common::Extraction::ImportKind::AUTOLOAD
          return constant_receiver?(node.receiver)
        end

        node.receiver.respond_to?(:full_name) &&
          node.receiver.full_name.delete_prefix('::') == 'Kernel'
      end

      def constant_receiver?(receiver)
        receiver.is_a?(Prism::ConstantReadNode) || receiver.is_a?(Prism::ConstantPathNode)
      end

      def import_argument(arguments, import_kind)
        case import_kind
        when Common::Extraction::ImportKind::AUTOLOAD
          arguments[1] if arguments.length == 2
        when Common::Extraction::ImportKind::LOAD
          arguments.first if LoadArguments.possible?(arguments)
        else
          arguments[0] if arguments.length == 1
        end
      end

      def invalidate_escaped_locals(node)
        @local_strings.invalidate_escaped(node)
        @local_strings.capture_scopes if %i[eval binding local_variable_set].include?(node.name)
      end
    end
    private_constant :ImportVisitor
  end
end
