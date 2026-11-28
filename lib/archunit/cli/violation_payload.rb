# frozen_string_literal: true

require_relative '../testing/violation_factory'
require_relative 'method_signature_payload'

module ArchUnit
  module CLI
    # Serializes violations without coupling their types to the report lifecycle.
    # @api private
    module ViolationPayload
      def self.build(violation)
        formatted = Testing::ViolationFactory.from_violation(violation)
        result = {
          type: violation.class.name, message: formatted.message, details: formatted.details
        }
        add_evidence(result, violation)
        result
      end

      def self.add_evidence(result, violation)
        case violation
        when Files::Assertion::CycleViolation
          result[:cycle_reporting] = 'witness' if violation.witness?
        when Files::Assertion::NamedCallViolation
          result[:call] = violation.call.to_h
        when Classes::Assertion::MethodSignatureViolation
          result[:method_signature] = MethodSignaturePayload.build(violation)
        when Classes::Assertion::EmptyClassSelectionViolation
          result[:class_selector] = violation.scope
        end
      end
      private_class_method :add_evidence
    end
  end
end
