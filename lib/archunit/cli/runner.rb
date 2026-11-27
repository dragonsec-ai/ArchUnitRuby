# frozen_string_literal: true

require_relative 'options'
require_relative 'configuration'
require_relative 'report'
require_relative '../extraction/analysis_observer'
require_relative 'baseline_run'

module ArchUnit
  module CLI
    # Internal command execution; technical errors never become successful rule checks.
    # @api private
    class Runner
      def initialize(arguments, out:, err:, cwd:)
        @options = Options.new(arguments, cwd:)
        @out = out
        @err = err
      end

      def run
        @options.parse!
        return information if %w[help version].include?(@options.command)

        @report = Report.new(@options)
        status = execute
        @report.write(out: @out, err: @err, format: @options.format)
        status
      rescue StandardError, SyntaxError, LoadError, NotImplementedError, SystemExit => e
        # An accidental exit in trusted configuration is not proof that rules passed.
        report_error(e)
      end

      private

      def report_error(error)
        @report ||= Report.new(@options)
        @report.fail_with(error, rule_name: @current_rule&.name)
        @report.write(out: @out, err: @err, format: @options.format)
        2
      end

      def information
        @out.puts(@options.command == 'help' ? @options.parser.to_s : ArchUnit::VERSION)
        0
      end

      def execute
        return initialize_configuration if @options.command == 'init'

        rules = Configuration.new(@options.project_root).load(@options.config_path)
        return explain(rules) if @options.command == 'explain'

        check(rules)
      end

      def initialize_configuration
        ensure_missing_configuration
        File.open(@options.config_path, File::WRONLY | File::CREAT | File::EXCL) do |file|
          file.write(Configuration::STARTER)
        end
        @report.finish('initialized')
        0
      end

      def ensure_missing_configuration
        # Windows exclusive creation may follow a dangling symlink; inspect the entry itself.
        File.lstat(@options.config_path)
        raise Errno::EEXIST, @options.config_path
      rescue Errno::ENOENT
        nil
      end

      def explain(rules)
        rules.each { |rule| @report.add_rule(rule) }
        @report.finish('configured')
        0
      end

      def check(rules)
        Extraction.clear_graph_cache
        options = Common::FluentApi::CheckOptions.new(
          dependency_analysis: @options.dependency_analysis.to_sym,
          rails_imports: @options.rails_imports, rails_associations: @options.rails_associations,
          load_paths: @options.load_paths, source_exclusions: @options.source_exclusions,
          cycle_reporting: @options.cycle_reporting.to_sym
        )
        check_rules(rules, options)
        BaselineRun.new(@options).finish(@report, @evaluations)
      end

      def check_rules(rules, options)
        analysis = AnalysisReport.new
        @evaluations = []
        Extraction::AnalysisObserver.capture(analysis) do
          rules.each { |rule| check_rule(rule, options, analysis) }
        end
      ensure
        @report.payload[:analysis] = analysis.to_h
      end

      def check_rule(rule, options, analysis)
        @current_rule = rule
        violations = analysis.for_rule(rule.name) { rule.checkable.check(options) }
        @report.add_rule(rule, violations:, analysis: analysis.for_name(rule.name))
        @evaluations << [rule.name, violations]
      end
    end
  end
end
