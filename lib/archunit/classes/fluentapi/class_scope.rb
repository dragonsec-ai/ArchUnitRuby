# frozen_string_literal: true

require_relative '../../common/fluentapi/check_options'
require_relative '../../extraction/declarations'
require_relative '../projection/select_classes'
require_relative 'class_filters'
require_relative 'positive_class_condition_builder'

module ArchUnit
  # Inspection of bounded class declarations, kept separate from file graph rules.
  module Classes
    module FluentApi
      # Lazy scope. Chained filters narrow the inspection with AND semantics.
      class ClassScope
        def initialize(project_locator, filters: ClassFilters.empty)
          @project_locator = immutable_locator(project_locator)
          @filters = filters
          freeze
        end

        # Includes classes owned by this namespace or one of its subnamespaces.
        # @return [ClassScope]
        def in_namespace(name)
          adding(:namespace, name)
        end

        # Selects an exact normalized constant name, not a file name or pattern.
        # @return [ClassScope]
        def with_constant_name(name)
          adding(:constant, name)
        end

        # Requires statically known transitive superclass ancestry (not mixins).
        # @return [ClassScope]
        def descendants_of(name)
          adding(:ancestor, name)
        end

        # Begins a positive declaration rule without reading the project.
        # @return [PositiveClassConditionBuilder]
        def should
          PositiveClassConditionBuilder.new(self)
        end

        # @api private
        def identity
          @filters.to_h.transform_values { |names| names.sort.freeze }.freeze
        end

        # Reads a declaration snapshot. This is inspection, not a passing/failing rule.
        # @param options [CheckOptions, nil]
        # @return [ClassSelection]
        def selection(options = nil)
          options = Common::FluentApi::CheckOptions.resolve(options)
          inventory = ArchUnit::Extraction.extract_declarations(@project_locator, options:)
          Projection::SelectClasses.call(inventory, @filters)
        end

        private

        def adding(kind, name)
          self.class.new(@project_locator, filters: @filters.add(kind, name))
        end

        def immutable_locator(locator)
          locator = locator.to_path if locator.respond_to?(:to_path)
          return if locator.nil?
          return locator.dup.freeze if locator.is_a?(String) && !locator.empty?

          raise ArgumentError, 'project_locator must be a non-empty path or nil'
        end
      end
    end
  end
end
