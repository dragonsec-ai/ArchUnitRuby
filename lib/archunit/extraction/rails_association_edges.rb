# frozen_string_literal: true

require_relative 'constant_dependency_edge'

module ArchUnit
  module Extraction
    # Bounded Active Record name lookup over the same definitions as constant analysis.
    class RailsAssociationEdges
      def initialize(definitions, profile)
        @definitions = definitions
        @profile = profile
      end

      def from(source, sites)
        @profile&.increment(:rails_association_sites, sites.length)
        sites.filter_map { |site| resolve(source, site) }
      end

      private

      def resolve(source, site)
        locations = candidate_locations(site)
        return unmodeled(:unresolved_rails_associations) if locations.empty?
        return unmodeled(:ambiguous_rails_associations) if locations.map(&:source).uniq.length > 1

        location = locations.find(&:class_declaration)
        return unmodeled(:unresolved_rails_associations) unless location

        ConstantDependencyEdge.build(source, site, location, Common::Extraction::ImportKind::RAILS_ASSOCIATION)
      end

      def candidate_locations(site)
        return [] unless site.name

        name = candidates(site).find { |candidate| @definitions.key?(candidate) }
        @definitions.fetch(name, [])
      end

      def candidates(site)
        name = site.name
        return [name.delete_prefix('::')] if name.start_with?('::')

        parts = site.model.split('::')
        prefixed = parts.length.downto(1).map do |length|
          "#{parts.take(length).join('::')}::#{name}"
        end
        parts.last == name ? [name, *prefixed] : [*prefixed, name]
      end

      def unmodeled(counter)
        @profile&.increment(counter)
        nil
      end
    end
    private_constant :RailsAssociationEdges
  end
end
