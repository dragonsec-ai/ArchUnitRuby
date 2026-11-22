# frozen_string_literal: true

require_relative 'baseline_document'
require_relative 'baseline_ledger'

module ArchUnit
  module CLI
    # Baselines classify evaluated violations; they never skip source or alter Checkable results.
    # @api private
    class BaselineRun
      def initialize(options)
        @options = options
      end

      def finish(report, evaluations)
        return finish_normal(report) unless @options.baseline_path || @options.command == 'baseline'

        records = records_for(report, evaluations)
        return create(report, records) if @options.command == 'baseline'

        apply(report, records)
      end

      private

      def finish_normal(report)
        failed = report.payload[:rules].any? { |rule| rule[:status] == 'failed' }
        report.finish(failed ? 'failed' : 'passed')
        failed ? 1 : 0
      end

      def records_for(report, evaluations)
        evaluations.flat_map do |name, violations|
          context = BaselineContext.for(name, report.payload[:analysis], @options.project_root)
          violations.map { |violation| BaselineFingerprint.entry(name, violation, context) }
        end
      end

      def create(report, records)
        entries = BaselineLedger.group(records)
        BaselineDocument.write(@options.output_path, entries, force: @options.force)
        report.payload[:baseline] = { status: 'created', path: @options.output_path,
                                      accepted_count: records.length, entries: entries.length }
        report.finish('baseline_created')
        0
      end

      def apply(report, records)
        ledger = BaselineLedger.new(BaselineDocument.load(@options.baseline_path))
        classify(report, records, ledger)
        finish_baseline(report, ledger.stale_entries)
      end

      def classify(report, records, ledger)
        report.payload[:rules].each do |rule|
          rule[:violations].each do |violation|
            violation[:baseline] = ledger.classify(records.shift)
          end
          update_rule_status(rule) unless rule[:violations].empty?
        end
      end

      def update_rule_status(rule)
        accepted = rule[:violations].all? { |value| value[:baseline][:status] == 'accepted' }
        rule[:status] = accepted ? 'accepted' : 'failed'
      end

      def finish_baseline(report, stale)
        summary = baseline_summary(report, stale)
        report.payload[:baseline] = summary.merge(status: 'checked', path: @options.baseline_path)
        failed = summary[:new_count].positive? || summary[:stale_count].positive?
        clean_status = summary[:accepted_count].positive? ? 'accepted' : 'passed'
        report.finish(failed ? 'failed' : clean_status)
        failed ? 1 : 0
      end

      def baseline_summary(report, stale)
        violations = report.payload[:rules].flat_map { |rule| rule[:violations] }
        accepted = violations.count { |v| v[:baseline][:status] == 'accepted' }
        { accepted_count: accepted, new_count: violations.length - accepted,
          stale_count: stale.sum { |entry| entry['count'] }, stale_entries: stale }
      end
    end
  end
end
