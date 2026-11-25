# frozen_string_literal: true

require_relative '../common/extraction/edge'

module ArchUnit
  module Extraction
    # Shared source/definition evidence construction for indexed dependencies.
    module ConstantDependencyEdge
      def self.build(source, reference, location, kind)
        return if source == location.source

        evidence = Common::Extraction::DependencyEvidence.new(
          source:, kind:, name: reference.name, line_number: reference.line_number,
          end_line: reference.end_line, target_line_number: location.line_number
        )
        Common::Extraction::Edge.new(
          source:, target: location.source, external: false,
          import_kinds: [kind], evidence: [evidence]
        )
      end
    end
    private_constant :ConstantDependencyEdge
  end
end
