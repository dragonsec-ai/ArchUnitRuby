# frozen_string_literal: true

require_relative 'declared_method_condition'

module ArchUnit
  module Classes
    module FluentApi
      # Positive mood for declaration-based class rules.
      class PositiveClassConditionBuilder
        def initialize(scope)
          @scope = scope
          freeze
        end

        # Requires a direct written method compatible with the specified call shape.
        # @param signature [ArchUnit::MethodSignature]
        # @return [DeclaredMethodCondition]
        def declare_method(signature)
          DeclaredMethodCondition.new(@scope, signature)
        end
      end
    end
  end
end
