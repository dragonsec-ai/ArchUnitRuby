# frozen_string_literal: true

require_relative 'layered_architecture'
require_relative 'rails_import_coverage'
require_relative '../../error/user_error'

module ArchUnit
  module Layers
    module FluentApi
      # Completed preset: existing layer assertions plus an explicit ambiguity guard.
      class PresetRule
        include Common::FluentApi::Checkable

        attr_reader :name, :architecture

        def initialize(name:, architecture:)
          unless name.is_a?(Symbol) && architecture.is_a?(LayeredArchitecture)
            raise ArgumentError, 'preset requires a Symbol name and LayeredArchitecture'
          end

          @name = name
          @architecture = architecture
          freeze
        end

        private

        def perform_check(options)
          graph = ArchUnit::Extraction.extract_graph(architecture.project_locator, options:)
          coverage = RailsImportCoverage.for(name, options, architecture.layer_definitions.size)
          validate_files(graph, coverage)
          architecture.check(options.with(clear_cache: false)).tap do |violations|
            coverage&.finish(graph) if violations.empty?
          end
        end

        def validate_files(graph, coverage)
          graph.each do |edge|
            next if edge.external || edge.source != edge.target

            layer = validate_membership(edge.source)
            coverage&.record(edge.source, layer)
          end
        end

        def validate_membership(path)
          matches = architecture.layer_definitions.select { |layer| layer.matches?(path) }
          return matches.first if matches.length <= 1

          names = matches.map(&:name).join(', ')
          raise UserError, "preset file '#{path}' matches multiple layers: #{names}"
        end
      end
    end
  end
end
