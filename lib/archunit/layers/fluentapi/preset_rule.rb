# frozen_string_literal: true

require_relative 'layered_architecture'
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
          graph.each do |edge|
            validate_membership(edge.source) if edge.source == edge.target && !edge.external
          end
          architecture.check(options.with(clear_cache: false))
        end

        def validate_membership(path)
          matches = architecture.layer_definitions.select { |layer| layer.matches?(path) }
          return if matches.length <= 1

          names = matches.map(&:name).join(', ')
          raise UserError, "preset file '#{path}' matches multiple layers: #{names}"
        end
      end
    end
  end
end
