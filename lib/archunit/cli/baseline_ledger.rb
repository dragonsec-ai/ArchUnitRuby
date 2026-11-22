# frozen_string_literal: true

module ArchUnit
  module CLI
    # One-to-one matching; duplicate occurrences cannot share one accepted-debt entry.
    # @api private
    class BaselineLedger
      def initialize(entries)
        @entries = entries
        @remaining = entries.to_h { |entry| [entry['fingerprint'], entry['count']] }
      end

      def classify(entry)
        id = entry&.fetch('fingerprint')
        accepted = id && @remaining.fetch(id, 0).positive?
        @remaining[id] -= 1 if accepted
        { status: accepted ? 'accepted' : 'new', fingerprint: id }
      end

      def stale_entries
        @entries.filter_map do |entry|
          count = @remaining.fetch(entry['fingerprint'])
          entry.merge('count' => count) if count.positive?
        end
      end

      def self.group(records)
        if records.any?(&:nil?)
          raise ArgumentError, 'cannot baseline empty, custom/unsupported or unobserved violations'
        end

        groups = records.group_by { |entry| entry['fingerprint'] }.values
        entries = groups.map { |group| group.first.merge('count' => group.length) }
        entries.sort_by { |entry| entry['fingerprint'] }
      end
    end
  end
end
