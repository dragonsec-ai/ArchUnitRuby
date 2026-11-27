# frozen_string_literal: true

require_relative 'tarjan_scc'

module ArchUnit
  module Common
    module Projection
      module Cycles
        # Finds one reproducible non-self cycle in each cyclic component, without enumeration.
        class CycleWitnesses
          def self.call(adjacency)
            new(adjacency).call
          end

          def initialize(adjacency)
            @adjacency = adjacency.transform_values(&:sort)
          end

          def call
            TarjanScc.call(@adjacency).select { |component| component.length > 1 }
                     .sort_by(&:first).map { |component| witness(component) }.freeze
          end

          private

          def witness(component)
            start = component.first
            members = component.to_set
            next_vertex = @adjacency.fetch(start).find do |target|
              target != start && members.include?(target)
            end
            parents = search(next_vertex, start, members)
            restore_path(start, parents)
          end

          def search(first, start, members)
            queue = [first]
            parents = { first => nil }
            queue.each do |current|
              break if current == start

              enqueue_neighbours(current, parents, queue, members)
            end
            parents
          end

          def enqueue_neighbours(current, parents, queue, members)
            @adjacency.fetch(current).each do |neighbour|
              next if parents.key?(neighbour) || !members.include?(neighbour)

              parents[neighbour] = current
              queue << neighbour
            end
          end

          def restore_path(start, parents)
            path = []
            current = start
            until current.nil?
              path << current
              current = parents.fetch(current)
            end
            # Shared cycle projection attaches the closing edge itself.
            [start, *path.drop(1).reverse].freeze
          end
        end
      end
    end
  end
end
