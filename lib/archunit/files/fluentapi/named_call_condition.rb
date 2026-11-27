# frozen_string_literal: true

require_relative '../../common/fluentapi/checkable'
require_relative '../../extraction/named_call_analysis'
require_relative '../assertion/named_calls'
require_relative 'file_rule_support'
require_relative 'named_call_options'

module ArchUnit
  module Files
    module FluentApi
      # Executable file rule forbidding named direct calls, with no runtime dispatch claims.
      class NamedCallCondition
        include Common::FluentApi::Checkable

        attr_reader :project_locator, :filters, :names, :call_options

        def initialize(mood, names, call_options:)
          @project_locator = mood.project_locator
          @filters = mood.filters
          @names = immutable_names(names)
          @call_options = NamedCallOptions.resolve(call_options)
          freeze
        end

        private

        def immutable_names(names)
          entries = names.is_a?(Array) ? names : [names]
          raise ArgumentError, 'provide at least one method name' if entries.empty?

          entries.to_set { |value| method_name(value) }.freeze
        end

        def method_name(value)
          if (value.is_a?(String) || value.is_a?(Symbol)) && !value.to_s.strip.empty?
            return value.to_s.encode(Encoding::UTF_8).freeze
          end

          raise ArgumentError, 'method names must be non-blank Strings or Symbols'
        end

        def perform_check(options)
          inventory = ArchUnit::Extraction.extract_named_calls(project_locator, options:)
          paths = FileRuleSupport.selected_paths(inventory.keys, filters)
          empty = empty_test_violation(paths, filters:, negated: true, options:)
          return empty if empty

          paths.flat_map do |path|
            Assertion.gather_named_call_violations(inventory.fetch(path), names,
                                                   receiver: call_options.receiver)
          end
        end
      end
    end
  end
end
