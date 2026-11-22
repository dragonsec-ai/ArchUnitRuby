# frozen_string_literal: true

require 'json'
require_relative '../version'
require_relative '../testing/violation_factory'
require_relative '../error/source_parse_error'
require_relative 'analysis_report'
require_relative 'analysis_text'

module ArchUnit
  module CLI
    # Internal presentation adapter reusing the shared violation vocabulary.
    # @api private
    class Report
      PARSE_GUIDANCE = [
        'Fix included Ruby syntax errors. If a file is a generator/ERB template rather than Ruby,',
        'exclude only that known non-source input with --exclude-source GLOB or',
        'CheckOptions.new(source_exclusions: [...]); selectors do not narrow source discovery.'
      ].freeze
      private_constant :PARSE_GUIDANCE

      attr_reader :payload

      def initialize(options)
        @payload = {
          schema_version: 1, archunit_version: ArchUnit::VERSION, command: options.command,
          project_root: options.project_root, config_path: options.config_path,
          dependency_analysis: options.dependency_analysis,
          rails_imports: options.rails_imports, load_paths: options.load_paths,
          source_exclusions: options.source_exclusions,
          status: 'error', rules: [], analysis: AnalysisReport.new.to_h
        }
      end

      def add_rule(rule, violations: nil, analysis: nil)
        payload[:rules] << {
          name: rule.name, rationale: rule.checkable.rationale, status: rule_status(violations),
          analysis: analysis || { status: 'unavailable', scope_ids: [] },
          violations: (violations || []).map { |violation| violation_payload(violation) }
        }
      end

      def finish(status)
        payload[:status] = status
        payload[:summary] = {
          rule_count: payload[:rules].length,
          violation_count: payload[:rules].sum { |rule| rule[:violations].length }
        }
        self
      end

      def fail_with(error, rule_name: nil)
        payload[:error] = { type: error.class.name, message: error.message, rule_name: }
        if error.is_a?(SourceParseError)
          payload[:error][:diagnostics] = error.diagnostics.map(&:to_h)
          payload[:error][:guidance] = PARSE_GUIDANCE
        end
        finish('error')
      end

      def write(out:, err:, format:)
        return out.puts(JSON.pretty_generate(payload)) if format == 'json'
        return write_error(err) if payload[:error]

        write_text(out)
      end

      private

      def write_error(err)
        err.puts("ArchUnit error: #{payload[:error][:message]}")
        payload[:error].fetch(:guidance, []).each { |line| err.puts(line) }
        AnalysisText.write(payload[:analysis], err)
      end

      def rule_status(violations)
        return 'not_checked' unless violations

        violations.empty? ? 'passed' : 'failed'
      end

      def violation_payload(violation)
        formatted = Testing::ViolationFactory.from_violation(violation)
        { type: violation.class.name, message: formatted.message, details: formatted.details }
      end

      def write_text(out)
        write_header(out)
        write_notice(out)
        payload[:rules].each { |rule| write_rule(rule, out) }
        AnalysisText.write(payload[:analysis], out)
      end

      def write_header(out)
        out.puts("ArchUnit #{ArchUnit::VERSION} — #{payload[:status]} " \
                 "(#{payload[:dependency_analysis]})")
        out.puts("Project: #{payload[:project_root]}\nConfiguration: #{payload[:config_path]}")
      end

      def write_notice(out)
        out.puts('Rails require_dependency imports: enabled') if payload[:rails_imports]
        case payload[:status]
        when 'configured'
          out.puts('Rules are configured, not evaluated.')
        when 'initialized'
          out.puts('Review and customize the trusted Ruby configuration before checking.')
        end
      end

      def write_rule(rule, out)
        out.puts("[#{rule[:status]}] #{rule[:name]}")
        out.puts("  Because: #{rule[:rationale]}") if rule[:rationale]
        rule[:violations].each do |violation|
          out.puts("  #{violation[:message]}\n    #{violation[:details]}")
        end
      end
    end
  end
end
