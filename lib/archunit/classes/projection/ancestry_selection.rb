# frozen_string_literal: true

require_relative 'parent_links'

module ArchUnit
  module Classes
    module Projection
      # Iterative memoized traversal of a bounded, single-superclass declaration graph.
      class AncestrySelection
        def initialize(parents, target)
          @parents = parents
          @target = target
          @results = {}
        end

        def status(name)
          return @results.fetch(name) if @results.key?(name)

          compute(name)
          @results.fetch(name)
        end

        private

        def compute(name)
          path = {}
          current = name
          until @results.key?(current)
            return record_cycle(path) if path.key?(current)
            return finish(path, current) if end_of_chain?(current)

            path[current] = true
            current = @parents.fetch(current)
          end
          propagate(path, @results.fetch(current))
        end

        def end_of_chain?(name)
          parent = @parents.fetch(name)
          parent.nil? || parent == ParentLinks::UNKNOWN
        end

        def finish(path, name)
          result = @parents.fetch(name).nil? ? :not_matched : :unresolved_ancestry
          @results[name] = result
          propagate(path, result)
        end

        def record_cycle(path)
          path.each_key { |name| @results[name] = :cyclic_ancestry }
        end

        def propagate(path, result)
          path.keys.reverse_each do |name|
            result = :matched if result != :cyclic_ancestry && @parents.fetch(name) == @target
            @results[name] = result
          end
        end
      end
      private_constant :AncestrySelection
    end
  end
end
