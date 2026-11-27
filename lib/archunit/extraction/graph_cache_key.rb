# frozen_string_literal: true

module ArchUnit
  module Extraction
    # Execution-only options are excluded; source exclusions already live in the pattern key.
    module GraphCacheKey
      REPRESENTED_ELSEWHERE = %i[
        allow_empty_tests logging clear_cache source_exclusions cycle_reporting
      ].freeze
      private_constant :REPRESENTED_ELSEWHERE

      def self.build(root, patterns, options)
        [root.to_s.tr('\\', '/').freeze, patterns.sort.freeze, analysis_toggles(options)].freeze
      end

      def self.analysis_toggles(options)
        options.class.members.filter_map do |member|
          next if REPRESENTED_ELSEWHERE.include?(member)

          [member, options.public_send(member)].freeze
        end.freeze
      end
      private_class_method :analysis_toggles
    end
    private_constant :GraphCacheKey
  end
end
