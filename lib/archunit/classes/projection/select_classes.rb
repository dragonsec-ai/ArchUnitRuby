# frozen_string_literal: true

require_relative 'ancestry_selection'
require_relative 'declaration_owners'

module ArchUnit
  module Classes
    module Projection
      # Pure selection; all IO and snapshot management live in extraction.
      # @api private
      class SelectClasses
        def self.call(inventory, filters)
          new(inventory, filters).call
        end

        def initialize(inventory, filters)
          @owners = DeclarationOwners.new(inventory)
          @filters = filters
          @matches = []
          @uncertainties = []
          @ancestors = ancestry_queries
        end

        def call
          if @filters.possible?
            @owners.names.each { |name| classify(name) }
            @owners.unresolved.each { |site| classify_unresolved(site) }
          end
          ClassSelection.new(matches: @matches.freeze, uncertainties: @uncertainties.freeze)
        end

        private

        def ancestry_queries
          return {} if @filters.ancestors.empty?

          parents = ParentLinks.build(@owners)
          @filters.ancestors.to_h { |target| [target, AncestrySelection.new(parents, target)] }
        end

        def classify(name)
          return unless @filters.matches_name?(name) && @owners.candidate?(name)
          return if @ancestors.key?(name)

          reason = @owners.certainty_reason(name)
          return uncertain(name, reason) if reason

          classify_ancestry(name)
        end

        def classify_ancestry(name)
          states = @ancestors.transform_values { |traversal| traversal.status(name) }
          return if states.value?(:not_matched)

          unresolved = states.reject { |_target, status| status == :matched }
          unresolved.each { |ancestor, reason| uncertain(name, reason, ancestor) }
          @matches << @owners.declared_class(name) if unresolved.empty?
        end

        def uncertain(name, reason, ancestor = nil)
          @uncertainties << UncertainClass.new(
            name:, reason:, ancestor:, declarations: @owners.declarations(name)
          )
        end

        def classify_unresolved(site)
          return unless @filters.unresolved_name_possible?(site.written_name)

          @uncertainties << UncertainClass.new(
            name: nil, reason: :unresolved_owner, ancestor: nil, declarations: [site].freeze
          )
        end
      end
    end
  end
end
