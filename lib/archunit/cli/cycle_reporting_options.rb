# frozen_string_literal: true

module ArchUnit
  module CLI
    # Parsing and preflight validation for the file cycle report policy.
    # @api private
    module CycleReportingOptions
      def cycle_reporting
        @cycle_reporting || 'exhaustive'
      end

      private

      def cycle_reporting_option(options)
        options.on('--cycle-reporting MODE', %w[exhaustive witness],
                   'File cycles: exhaustive (default) or one witness per cyclic group') do |value|
          @cycle_reporting = value
        end
      end

      def validate_cycle_reporting
        return if cycle_reporting != 'witness' || %w[help version].include?(command)

        if baseline_path || command == 'baseline'
          raise ArgumentError, 'cycle witness reporting is incompatible with baselines'
        end
        return if command == 'check'

        raise ArgumentError, '--cycle-reporting witness is only valid for check'
      end
    end
  end
end
