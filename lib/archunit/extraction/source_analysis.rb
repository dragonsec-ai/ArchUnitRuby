# frozen_string_literal: true

require_relative 'analysis_observer'
require_relative 'analysis_snapshot'

module ArchUnit
  module Extraction
    # Records a complete source-metric pass or an unavailable, failed pass.
    # @api private
    module SourceAnalysis
      def self.observe(discovery)
        result = yield
        publish(discovery, count: discovery.files.length, status: 'analyzed')
        result
      rescue StandardError
        publish(discovery, count: nil, status: 'error')
        raise
      end

      def self.publish(discovery, count:, status:)
        AnalysisObserver.record(AnalysisSnapshot.source(discovery, count:, status:))
      end
      private_class_method :publish
    end
  end
end
