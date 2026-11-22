# frozen_string_literal: true

require_relative 'extraction_profile'

module ArchUnit
  module Extraction
    # Independent graph counts, optionally forwarding work to a caller's timing profile.
    # @api private
    class AnalysisProfile
      def initialize(delegate)
        @delegate = delegate
        @counts = ExtractionProfile.new
      end

      def increment(counter, amount = 1)
        @counts.increment(counter, amount)
        @delegate&.increment(counter, amount)
      end

      def measure(stage, &)
        ExtractionProfile.measure(@delegate, stage, &)
      end

      def counters
        @counts.counters
      end
    end
    private_constant :AnalysisProfile
  end
end
