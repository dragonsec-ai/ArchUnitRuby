# frozen_string_literal: true

require_relative '../../common/fluentapi/checkable'
require_relative '../assertion/empty_class_selection_violation'
require_relative '../assertion/method_signatures'
require_relative 'method_signature'

module ArchUnit
  module Classes
    module FluentApi
      # Executable contract against ordinary declarations on every selected class.
      class DeclaredMethodCondition
        include Common::FluentApi::Checkable

        def initialize(scope, signature)
          unless signature.is_a?(ArchUnit::MethodSignature)
            raise ArgumentError, 'declare_method requires a MethodSignature'
          end

          @scope = scope
          @signature = signature
          freeze
        end

        private

        def perform_check(options)
          selection = @scope.selection(options)
          return empty_selection(options) if selection.status == :empty

          Assertion.gather_method_signature_violations(selection, @signature, @scope.identity)
        end

        def empty_selection(options)
          options.allow_empty_tests? ? [] : [Assertion::EmptyClassSelectionViolation.new(@scope.identity)]
        end
      end
    end
  end
end
