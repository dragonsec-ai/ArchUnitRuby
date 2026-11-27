# frozen_string_literal: true

module ArchUnit
  module Classes
    module Projection
      # Builds only unambiguous written superclass links. Nil is a declared-graph end.
      module ParentLinks
        UNKNOWN = :unresolved_ancestry

        def self.build(owners)
          owners.names.to_h { |name| [name, parent(owners, name)] }.freeze
        end

        def self.parent(owners, name)
          return UNKNOWN unless owners.known_class?(name)

          scopes = owners.declarations(name).to_h { |decl| [decl.site, decl.nesting] }
          targets = owners.superclass_sites(name).map do |site|
            resolve(site.written_target, scopes.fetch(site.owner), owners)
          end.uniq
          return targets.first if targets.size < 2

          UNKNOWN
        end

        def self.resolve(written, nesting, owners)
          return UNKNOWN if written.nil?

          resolved = bounded_name(written, nesting, owners)
          owners.known_class?(resolved) ? resolved : UNKNOWN
        end

        def self.bounded_name(written, nesting, owners)
          return written.delete_prefix('::') if written.start_with?('::')
          return written if nesting.empty?
          return if written.include?('::')

          lexical_name(written, nesting, owners)
        end

        def self.lexical_name(written, nesting, owners)
          return if nesting.any?(&:nil?)

          nesting.lazy.map { |prefix| "#{prefix}::#{written}" }
                 .find { |candidate| owners.known_name?(candidate) }
        end
        private_class_method :parent, :resolve, :bounded_name, :lexical_name
      end
      private_constant :ParentLinks
    end
  end
end
