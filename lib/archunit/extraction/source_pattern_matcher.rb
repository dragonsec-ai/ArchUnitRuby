# frozen_string_literal: true

module ArchUnit
  module Extraction
    # Compiles discovery-invariant glob decisions once; matching itself is pure.
    # @api private
    class SourcePatternMatcher
      FLAGS = File::FNM_DOTMATCH | File::FNM_PATHNAME

      def initialize(patterns)
        @basenames = {}
        @globs = []
        patterns.each { |pattern| compile(pattern) }
        @basenames.freeze
        @globs.freeze
        freeze
      end

      def excluded?(identifier, basename)
        @basenames.key?(basename) || @globs.any? do |pattern, path_pattern|
          File.fnmatch?(pattern, path_pattern ? identifier : basename, FLAGS)
        end
      end

      private

      def compile(pattern)
        candidate = pattern.delete_prefix('/')
        path_pattern = pattern.start_with?('/') || candidate.include?('/')
        if !path_pattern && !candidate.match?(/[*?\[]/)
          @basenames[candidate.freeze] = true
        else
          @globs << [candidate.freeze, path_pattern].freeze
        end
      end
    end
    private_constant :SourcePatternMatcher
  end
end
