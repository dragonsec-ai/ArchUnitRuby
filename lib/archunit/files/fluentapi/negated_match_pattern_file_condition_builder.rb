# frozen_string_literal: true

require_relative 'match_pattern_file_condition_builder'
require_relative 'named_call_condition'

module ArchUnit
  module Files
    module FluentApi
      # The `should_not` mood for file predicates.
      class NegatedMatchPatternFileConditionBuilder < MatchPatternFileConditionBuilder
        def initialize(scope)
          super(scope, negated: true)
        end

        # Forbids direct syntactic calls by method name in the selected files.
        # @param names [String, Symbol, Array<String, Symbol>]
        # @param options [NamedCallOptions, nil]
        # @return [NamedCallCondition]
        def contain_calls_named(names, options = nil)
          NamedCallCondition.new(self, names, call_options: options)
        end
      end
    end
  end
end
