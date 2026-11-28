# frozen_string_literal: true

require 'json'

module ArchUnit
  module CLI
    # One explicit adapter for report evidence and stable accepted-debt identities.
    # @api private
    module MethodSignaturePayload
      POLICY = 'declared_shape_v1'
      private_constant :POLICY

      def self.build(violation)
        finding = violation.finding
        shared_fields(finding).merge(
          'unknown' => violation.unknown?, 'ancestor' => finding.ancestor,
          'declarations' => finding.declarations.map { |fact| fact.site.to_h },
          'candidates' => finding.candidates.map { |method| with_site(method) }
        )
      end

      def self.identity(violation)
        if violation.unknown?
          raise ArgumentError, 'cannot baseline an unknown method signature or class selection'
        end

        finding = violation.finding
        shared_fields(finding).merge(
          'definitions' => finding.declarations.map { |fact| fact.site.file }.uniq.sort,
          'observed' => observed_shapes(finding.candidates)
        )
      end

      def self.shared_fields(finding)
        {
          'policy' => POLICY, 'owner' => finding.owner, 'reason' => finding.reason.to_s,
          'selector' => finding.scope.transform_keys(&:to_s),
          'expected' => finding.expected.to_h.transform_keys(&:to_s)
        }
      end

      def self.shape(method)
        { 'name' => method.name.to_s, 'scope' => method.scope.to_s,
          'parameters' => method.parameters.map { |param| [param.kind.to_s, param.name&.to_s] } }
      end

      def self.with_site(method)
        shape(method).merge('site' => method.site.to_h, 'context' => method.context.to_s)
      end

      def self.observed_shapes(methods)
        methods.map { |method| shape(method).merge('file' => method.site.file) }
               .sort_by { |value| JSON.generate(value) }
      end
      private_class_method :shared_fields, :shape, :with_site, :observed_shapes
    end
  end
end
