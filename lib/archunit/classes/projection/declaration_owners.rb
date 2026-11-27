# frozen_string_literal: true

require_relative 'class_selection'

module ArchUnit
  module Classes
    module Projection
      # Groups immutable declaration sites without silently dropping reopens or kind conflicts.
      class DeclarationOwners
        attr_reader :unresolved, :names

        def initialize(inventory)
          @by_name = inventory.namespaces.group_by(&:name)
          @unresolved = @by_name.delete(nil) || []
          @names = @by_name.keys.sort
          @methods = inventory.method_declarations.group_by(&:owner)
          @relationships = inventory.relationships.group_by(&:owner)
        end

        def declarations(name)
          @by_name.fetch(name).dup.freeze
        end

        def candidate?(name)
          @by_name.fetch(name).any? { |decl| decl.kind == :class }
        end

        def certainty_reason(name)
          sites = @by_name.fetch(name)
          kinds = sites.map(&:kind)
          return :conflicting_constant_write if kinds.include?(:constant_write)
          return :conflicting_declaration_kind if kinds.include?(:module)
          return :uncertain_namespace_owner if uncertain_prefix?(name)

          :conditional_or_dynamic_declaration if sites.any? { |decl| decl.context != :direct }
        end

        def known_class?(name)
          @by_name.key?(name) && candidate?(name) && certainty_reason(name).nil?
        end

        def known_name?(name)
          @by_name.key?(name)
        end

        def declared_class(name)
          sites = declarations(name)
          DeclaredClass.new(
            name:, declarations: sites, method_declarations: for_sites(@methods, sites),
            relationships: for_sites(@relationships, sites)
          )
        end

        def superclass_sites(name)
          for_sites(@relationships, @by_name.fetch(name)).select { |ref| ref.kind == :superclass }
        end

        private

        def uncertain_prefix?(name)
          prefix = name
          while prefix.include?('::')
            prefix = prefix.rpartition('::').first
            sites = @by_name.fetch(prefix, [])
            return true if conflicting_prefix?(sites)
          end
          false
        end

        def conflicting_prefix?(sites)
          sites.map(&:kind).uniq.size > 1 ||
            sites.any? { |decl| decl.kind == :constant_write || decl.context != :direct }
        end

        def for_sites(map, sites)
          sites.flat_map { |decl| map.fetch(decl.site, []) }.freeze
        end
      end
      private_constant :DeclarationOwners
    end
  end
end
