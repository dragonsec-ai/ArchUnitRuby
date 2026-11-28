# frozen_string_literal: true

require_relative 'callable_shape'
require_relative 'method_signature_violation'

module ArchUnit
  module Classes
    # Pure checks on explicit class/method declarations.
    module Assertion
      module_function

      def gather_method_signature_violations(selection, signature, scope)
        definite = selection.matches.filter_map { |klass| check_signature(klass, signature, scope) }
        unresolved = selection.uncertainties.map do |subject|
          signature_violation(subject, signature, scope, [].freeze, subject.reason)
        end
        definite + unresolved
      end

      def check_signature(subject, signature, scope)
        candidates = method_candidates(subject, signature)
        reason = signature_failure(candidates, signature)
        signature_violation(subject, signature, scope, candidates, reason) if reason
      end
      private_class_method :check_signature

      def method_candidates(subject, signature)
        subject.method_declarations.select do |method|
          (method.scope == signature.scope || method.scope == :unknown) &&
            method.name.to_s.encode(Encoding::UTF_8) == signature.name
        end.freeze
      end
      private_class_method :method_candidates

      def signature_failure(candidates, signature)
        return :missing_declaration if candidates.empty?
        return :uncertain_method_declaration if candidates.any? { |method| uncertain?(method) }

        matching = candidates.count do |method|
          CallableShape.matches?(method.parameters, signature)
        end
        return :incompatible_signature if matching.zero?

        :conflicting_signatures if matching != candidates.size
      end
      private_class_method :signature_failure

      def uncertain?(method)
        method.context != :direct || method.scope == :unknown
      end
      private_class_method :uncertain?

      def signature_violation(subject, expected, scope, candidates, reason)
        ancestor = subject.ancestor if subject.respond_to?(:ancestor)
        finding = MethodSignatureViolation::Finding.new(
          owner: subject.name, expected:, reason:, candidates:, declarations: subject.declarations,
          scope:, ancestor:
        )
        MethodSignatureViolation.new(finding)
      end
      private_class_method :signature_violation
    end
  end
end
