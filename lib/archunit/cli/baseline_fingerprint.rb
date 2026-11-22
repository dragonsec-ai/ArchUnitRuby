# frozen_string_literal: true

require 'digest'
require 'json'
require_relative 'baseline_identity'
require_relative 'baseline_context'

module ArchUnit
  module CLI
    # Version-one fingerprints are structured data, not formatter prose or source locations.
    # @api private
    module BaselineFingerprint
      def self.entry(name, violation, context)
        data = BaselineIdentity.for(violation)
        return unless data && context

        entry = { 'rule' => name, 'type' => violation.class.name, 'data' => data,
                  'context' => context }
        entry.merge('fingerprint' => digest(entry), 'count' => 1)
      end

      def self.digest(entry)
        identity = entry.except('fingerprint', 'count')
        Digest::SHA256.hexdigest(JSON.generate(canonical(identity)))
      end

      def self.canonical(value)
        case value
        when Hash then value.keys.sort.to_h { |key| [key, canonical(value.fetch(key))] }
        when Array then value.map { |item| canonical(item) }
        else value
        end
      end
    end
  end
end
