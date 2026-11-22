# frozen_string_literal: true

module ArchUnit
  module Extraction
    # Scoped, fiber-local diagnostics. Nothing is retained after capture ends.
    # @api private
    module AnalysisObserver
      KEY = :archunit_analysis_observer
      private_constant :KEY

      def self.capture(observer)
        previous = Thread.current[KEY]
        Thread.current[KEY] = observer
        yield
      ensure
        Thread.current[KEY] = previous
      end

      def self.record(snapshot, cache_hit: false)
        Thread.current[KEY]&.observe(snapshot, cache_hit:)
      end
    end
  end
end
