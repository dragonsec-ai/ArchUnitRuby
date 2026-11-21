# frozen_string_literal: true

require 'prism'
require_relative '../common/extraction/import_kind'
require_relative 'load_arguments'

module ArchUnit
  module Extraction
    # Matches supported syntax, separating explicit framework vocabulary from default Ruby calls.
    class ImportCalls
      KINDS = {
        require: Common::Extraction::ImportKind::REQUIRE,
        require_relative: Common::Extraction::ImportKind::REQUIRE_RELATIVE,
        autoload: Common::Extraction::ImportKind::AUTOLOAD,
        load: Common::Extraction::ImportKind::LOAD,
        require_dependency: Common::Extraction::ImportKind::REQUIRE_DEPENDENCY
      }.freeze
      private_constant :KINDS

      def initialize(rails_imports:, source_policy:)
        unless [true, false].include?(rails_imports)
          raise ArgumentError, 'rails_imports must be true or false'
        end

        @rails_imports = rails_imports
        @source_policy = source_policy
      end

      def kind(node)
        value = KINDS[node.name]
        return unless value && enabled?(value) && supported_receiver?(node.receiver, value)

        value if argument(node.arguments&.arguments || [], value)
      end

      def path(arguments, kind)
        return if uncertain?(kind)
        if [Common::Extraction::ImportKind::LOAD,
            Common::Extraction::ImportKind::REQUIRE_DEPENDENCY].include?(kind)
          return LoadArguments.path(arguments)
        end

        argument(arguments, kind)
      end

      def uncertain?(kind)
        kind == Common::Extraction::ImportKind::REQUIRE_DEPENDENCY &&
          !@source_policy.allowed?(:rails_helpers)
      end

      private

      def enabled?(kind)
        @rails_imports || kind != Common::Extraction::ImportKind::REQUIRE_DEPENDENCY
      end

      def argument(arguments, kind)
        case kind
        when Common::Extraction::ImportKind::AUTOLOAD
          arguments[1] if arguments.length == 2
        when Common::Extraction::ImportKind::LOAD, Common::Extraction::ImportKind::REQUIRE_DEPENDENCY
          variable_argument(arguments, kind)
        else
          arguments.first if arguments.length == 1
        end
      end

      def variable_argument(arguments, kind)
        limit = kind == Common::Extraction::ImportKind::LOAD ? 2 : 1
        arguments.first if LoadArguments.possible?(arguments, max: limit)
      end

      def supported_receiver?(receiver, kind)
        return true if receiver.nil?
        if kind == Common::Extraction::ImportKind::REQUIRE_DEPENDENCY
          return receiver.is_a?(Prism::SelfNode)
        end
        if kind == Common::Extraction::ImportKind::AUTOLOAD
          return receiver.is_a?(Prism::ConstantReadNode) || receiver.is_a?(Prism::ConstantPathNode)
        end

        kernel_receiver?(receiver)
      end

      def kernel_receiver?(receiver)
        return receiver.name == :Kernel if receiver.is_a?(Prism::ConstantReadNode)

        receiver.is_a?(Prism::ConstantPathNode) && receiver.parent.nil? && receiver.name == :Kernel
      end
    end
    private_constant :ImportCalls
  end
end
