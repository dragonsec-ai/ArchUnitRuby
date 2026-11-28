# frozen_string_literal: true

require_relative '../../common/assertion/violation'

module ArchUnit
  module Classes
    module Assertion
      # Data describing a missing, incompatible, or uncertain written method contract.
      class MethodSignatureViolation < Common::Assertion::Violation
        Finding = Data.define(:owner, :expected, :reason, :candidates, :declarations, :scope,
                              :ancestor)
        CONFIRMED = %i[missing_declaration incompatible_signature].freeze
        private_constant :CONFIRMED

        attr_reader :finding

        def initialize(finding)
          raise ArgumentError, 'finding must be a method finding' unless finding.is_a?(Finding)

          @finding = finding
          super()
        end

        def unknown?
          !CONFIRMED.include?(finding.reason)
        end

        def ==(other)
          other.is_a?(self.class) && finding == other.finding
        end
        alias eql? ==

        def hash
          [self.class, finding].hash
        end
      end
    end
  end
end
