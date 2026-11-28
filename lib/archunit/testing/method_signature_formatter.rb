# frozen_string_literal: true

require_relative 'test_violation'
require_relative '../common/identifier_text'
require_relative '../classes/assertion/method_signature_violation'
require_relative '../classes/assertion/empty_class_selection_violation'

module ArchUnit
  module Testing
    # Describes the written call shape and where the analyzer found or expected it.
    module MethodSignatureFormatter
      FORMATTERS = {
        Classes::Assertion::EmptyClassSelectionViolation => :empty_class_selection,
        Classes::Assertion::MethodSignatureViolation => :method_signature
      }.freeze

      private

      def method_signature(violation)
        finding = violation.finding
        message = violation.unknown? ? 'Method signature unknown' : 'Declared signature violation'
        reason = finding.reason.to_s.tr('_', ' ')
        details = ["#{signature_summary(finding)}: #{reason}.",
                   "Source: #{signature_location(finding)}."].join(' ')
        TestViolation.new(message:, details:)
      end

      def empty_class_selection(violation)
        selectors = violation.scope.reject { |_kind, names| names.empty? }
        details = selectors.map { |kind, names| "#{kind}: #{identifier_list(names)}" }.join('; ')
        details = 'The unfiltered scope contained no declared classes.' if details.empty?
        TestViolation.new(message: 'No classes matched the rule scope', details:)
      end

      def signature_summary(finding)
        signature = finding.expected
        separator = signature.scope == :singleton ? '.' : '#'
        owner = Common::IdentifierText.utf8(finding.owner || '<unknown class>')
        keywords = identifier_list(signature.keywords)
        method = "#{owner}#{separator}#{Common::IdentifierText.utf8(signature.name)}"
        shape = "#{signature.positional} positional and keywords [#{keywords}]"
        "#{method} expects a declaration accepting #{shape} (block: #{signature.block})"
      end

      def identifier_list(names)
        names.map { |name| Common::IdentifierText.utf8(name) }.join(', ')
      end

      def signature_location(finding)
        fact = finding.candidates.first || finding.declarations.first
        site = fact.site
        "#{site.file}:#{site.line}:#{site.column}"
      end
    end
  end
end
