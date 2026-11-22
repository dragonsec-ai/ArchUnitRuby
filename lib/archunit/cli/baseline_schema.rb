# frozen_string_literal: true

require_relative 'baseline_fingerprint'

module ArchUnit
  module CLI
    # Pure format validation, including identity/data consistency (not authentication).
    # @api private
    module BaselineSchema
      HEADER = %w[entries fingerprint_version schema_version].freeze
      ENTRY = %w[context count data fingerprint rule type].freeze
      private_constant :HEADER, :ENTRY

      def self.validate(document)
        unless valid_header?(document)
          raise ArgumentError, 'invalid baseline schema (expected schema/fingerprint version 1)'
        end

        entries = document.fetch('entries').map { |entry| validate_entry(entry) }
        ids = entries.map { |entry| entry['fingerprint'] }
        raise ArgumentError, 'duplicate baseline fingerprints' unless ids.uniq.length == ids.length

        entries
      end

      def self.valid_header?(document)
        document.is_a?(Hash) && document.keys.sort == HEADER &&
          document.values_at('schema_version', 'fingerprint_version').all? { |v| v.eql?(1) } &&
          document['entries'].is_a?(Array) && document['entries'].length <= 10_000
      end

      def self.validate_entry(entry)
        unless entry.is_a?(Hash) && entry.keys.sort == ENTRY && valid_identity?(entry) &&
               valid_count?(entry['count']) &&
               entry['fingerprint'] == BaselineFingerprint.digest(entry)
          raise ArgumentError, 'invalid baseline entry or fingerprint'
        end

        entry
      end

      def self.valid_count?(value)
        value.is_a?(Integer) && value.between?(1, 1_000_000)
      end

      def self.valid_identity?(entry)
        %w[rule type].all? { |key| entry[key].is_a?(String) && !entry[key].empty? } &&
          entry['data'].is_a?(Hash) && entry['context'].is_a?(Array) && !entry['context'].empty?
      end
      private_class_method :valid_header?, :validate_entry, :valid_count?, :valid_identity?
    end
  end
end
