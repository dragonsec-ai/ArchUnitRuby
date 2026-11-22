# frozen_string_literal: true

module ArchUnit
  module CLI
    # Separate parsing keeps accepted-debt writes explicit and check commands read-only.
    # @api private
    module BaselineOptions
      attr_reader :baseline_path, :output_path

      def force
        @force || false
      end

      private

      def baseline_options(options)
        options.on('--baseline FILE', 'Check accepted debt (check only)') do |value|
          @baseline_path = File.expand_path(value, @cwd)
        end
        options.on('--output FILE', 'Write accepted debt (baseline command only)') do |value|
          @output_path = File.expand_path(value, @cwd)
        end
        options.on('--force', 'Replace existing regular baseline output') { @force = true }
      end

      def validate_baseline_options
        return if %w[help version].include?(command)

        if baseline_path && command != 'check'
          raise ArgumentError, '--baseline is only valid for check'
        end

        return validate_baseline_output if command == 'baseline'

        return unless output_path || force

        raise ArgumentError, '--output and --force are only valid for baseline'
      end

      def validate_baseline_output
        raise ArgumentError, 'baseline requires --output FILE' unless output_path
        return if File.extname(output_path) == '.json'

        raise ArgumentError, 'baseline output must have a .json extension'
      end
    end
  end
end
