# frozen_string_literal: true

module ArchUnit
  module Common
    module Extraction
      # Immutable, additive caller-owned source globs; never reads target configuration.
      module SourceExclusions
        module_function

        def normalize(value)
          unless value.is_a?(Array) && value.all?(String)
            raise ArgumentError,
                  'source_exclusions must be an Array of project-relative glob Strings'
          end

          value.map { |pattern| normalize_pattern(pattern) }.uniq.sort.freeze
        end

        def normalize_pattern(pattern)
          pattern = pattern.strip.tr('\\', '/').delete_prefix('./')
          validate_pattern(pattern)
          return pattern.freeze unless pattern.end_with?('/')

          directory = pattern.delete_suffix('/')
          prefix = directory.include?('/') ? '' : '**/'
          "#{prefix}#{directory}/**".freeze
        end
        private_class_method :normalize_pattern

        def validate_pattern(pattern)
          invalid = pattern.empty? || pattern == '/' || pattern.start_with?('!', '//') ||
                    pattern.match?(/[\0\r\n]|\A[a-z]:/i) || pattern.split('/').include?('..')
          return unless invalid

          raise ArgumentError,
                'source_exclusions require non-empty project-relative globs without negation, ' \
                'NUL/newlines, drive paths or parent traversal'
        end
        private_class_method :validate_pattern
      end
    end
  end
end
