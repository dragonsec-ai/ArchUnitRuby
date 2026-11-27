# frozen_string_literal: true

require_relative '../../extraction/analysis_observer'

module ArchUnit
  module Layers
    module FluentApi
      # Ephemeral CLI diagnostic, using only already validated layer memberships and graph edges.
      # @api private
      class RailsImportCoverage
        IMPORTS = %i[require require_relative autoload load require_dependency].freeze
        private_constant :IMPORTS

        def self.for(name, options, layer_count)
          return unless name == :rails && !options.constant_references?

          sink = ArchUnit::Extraction::AnalysisObserver.advisory_sink
          new(sink, layer_count) if sink
        end

        def initialize(sink, layer_count)
          @sink = sink
          @layer_count = layer_count
          @files = {}
          @present = Set.new
        end

        def record(path, layer)
          return unless layer

          @files[path] = true
          @present.add(layer.name)
        end

        def finish(graph)
          return unless @present.size == @layer_count
          return if graph.any? { |edge| scoped_import?(edge) }

          @sink.advise(:rails_no_scoped_imports)
        end

        private

        def scoped_import?(edge)
          !edge.external && edge.source != edge.target && @files.key?(edge.source) &&
            @files.key?(edge.target) && edge.import_kinds.intersect?(IMPORTS)
        end
      end
      private_constant :RailsImportCoverage
    end
  end
end
