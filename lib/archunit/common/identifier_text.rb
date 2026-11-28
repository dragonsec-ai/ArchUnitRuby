# frozen_string_literal: true

module ArchUnit
  module Common
    # Presentation only. Analysis compares the original identifier strings.
    # @api private
    module IdentifierText
      def self.utf8(identifier)
        identifier.encode(Encoding::UTF_8)
      rescue EncodingError
        identifier.dump
      end
    end
  end
end
