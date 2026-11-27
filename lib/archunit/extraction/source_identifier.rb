# frozen_string_literal: true

require_relative '../error/technical_error'

module ArchUnit
  module Extraction
    # A native path component must never be reinterpreted as two project components.
    # @api private
    module SourceIdentifier
      def self.validate(path)
        return path unless path.include?('\\')

        raise TechnicalError, "cannot represent Ruby source path #{path.inspect}: " \
                              'literal backslash; rename the path or exclude the source'
      end

      def self.root(path)
        native = path.to_s
        File::ALT_SEPARATOR ? native.tr(File::ALT_SEPARATOR, '/') : validate(native)
      end
    end
    private_constant :SourceIdentifier
  end
end
