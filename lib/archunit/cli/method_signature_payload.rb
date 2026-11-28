# frozen_string_literal: true

require 'json'
require_relative '../common/identifier_text'

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
          'unknown' => violation.unknown?, 'ancestor' => identifier(finding.ancestor),
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

      def self.selector(scope)
        scope.transform_keys(&:to_s).transform_values do |names|
          names.map { |name| identifier(name) }
        end
      end

      def self.shared_fields(finding)
        {
          'policy' => POLICY, 'owner' => identifier(finding.owner), 'reason' => finding.reason.to_s,
          'selector' => selector(finding.scope), 'expected' => expected_shape(finding.expected)
        }
      end

      def self.expected_shape(signature)
        keywords = signature.keywords.map { |name| identifier(name) }
        signature.to_h.transform_keys(&:to_s).merge(
          'name' => identifier(signature.name), 'keywords' => keywords
        )
      end

      def self.shape(method)
        parameters = method.parameters.map { |param| [param.kind.to_s, identifier(param.name)] }
        { 'name' => identifier(method.name), 'scope' => method.scope.to_s,
          'parameters' => parameters }
      end

      def self.identifier(value)
        return if value.nil?

        name = value.to_s
        return name if name.ascii_only? || name.encoding == Encoding::UTF_8

        # JSON alone transcodes distinct Ruby names to the same spelling.
        { 'text' => Common::IdentifierText.utf8(name), 'encoding' => name.encoding.name,
          'bytes' => name.unpack1('H*') }
      end

      def self.with_site(method)
        shape(method).merge('site' => method.site.to_h, 'context' => method.context.to_s)
      end

      def self.observed_shapes(methods)
        methods.map { |method| shape(method).merge('file' => method.site.file) }
               .sort_by { |value| JSON.generate(value) }
      end
      private_class_method :shared_fields, :expected_shape, :shape, :identifier, :with_site,
                           :observed_shapes
    end
  end
end
