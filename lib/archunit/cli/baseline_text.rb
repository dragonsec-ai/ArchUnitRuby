# frozen_string_literal: true

module ArchUnit
  module CLI
    # Accepted debt remains visible, including stale entries after an architectural improvement.
    # @api private
    module BaselineText
      def self.write(baseline, out)
        return unless baseline

        return created(baseline, out) if baseline[:status] == 'created'

        checked(baseline, out)
      end

      def self.created(baseline, out)
        out.puts("Baseline created: #{baseline[:path]} (#{baseline[:accepted_count]} violations).")
        out.puts('Review accepted debt before committing; this is not a clean architecture result.')
      end

      def self.checked(baseline, out)
        out.puts("Baseline: #{baseline[:accepted_count]} accepted, #{baseline[:new_count]} new, " \
                 "#{baseline[:stale_count]} stale. #{baseline[:path]}")
        baseline[:stale_entries].each do |entry|
          out.puts("  Stale: #{entry['rule']} — #{entry['type']} (#{entry['count']})")
        end
      end
      private_class_method :created, :checked
    end
  end
end
