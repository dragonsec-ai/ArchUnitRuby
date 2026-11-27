# frozen_string_literal: true

require_relative '../testing/violation_factory'
require 'json'

module ArchUnit
  module CLI
    # Explicit adapters: unknown/custom/empty-selection failures are never accepted implicitly.
    # @api private
    module BaselineIdentity
      TYPES = {
        Files::Assertion::FileDependencyViolation => :dependency,
        Files::Assertion::ExternalModuleDependencyViolation => :dependency,
        Files::Assertion::FilePatternViolation => :pattern,
        Files::Assertion::NamedCallViolation => :named_call,
        Files::Assertion::CycleViolation => :cycle,
        Layers::Assertion::LayerDependencyViolation => :layer,
        Slices::Assertion::SliceDependencyViolation => :slice,
        Metrics::Assertion::MetricThresholdViolation => :threshold
      }.freeze
      private_constant :TYPES

      def self.for(violation)
        adapter = TYPES[violation.class]
        send(adapter, violation) if adapter
      end

      def self.dependency(value)
        { 'edge' => edge(value.dependency), 'negated' => value.negated? }
      end

      def self.edge(value)
        pairs = value.cumulated_edges.map do |raw|
          [identifier(raw.source), identifier(raw.target), raw.external]
        end
        [identifier(value.source_label), identifier(value.target_label), pairs.uniq.sort]
      end

      def self.layer(value)
        { 'edge' => edge(value.dependency), 'source_layer' => value.source_layer,
          'target_layer' => value.target_layer, 'predicate' => value.rule.to_s }
      end

      def self.slice(value)
        dependency(value).merge('source_slice' => value.source_slice,
                                'target_slice' => value.target_slice,
                                'predicate' => value.rule.to_s)
      end

      def self.pattern(value)
        { 'file' => identifier(value.projected_node.label), 'filter' => filter(value.check_filter),
          'negated' => value.negated? }
      end

      def self.named_call(value)
        call = value.call
        { 'file' => identifier(call.file), 'name' => call.name, 'receiver' => call.receiver.to_s,
          'safe_navigation' => call.safe_navigation }
      end

      def self.filter(value)
        [value.regexp.source, value.regexp.options, value.target.to_s, value.matching.to_s,
         value.exclusions.map { |item| filter(item) }.sort_by { |item| JSON.generate(item) }]
      end

      def self.cycle(value)
        if value.witness?
          raise ArgumentError, 'cycle witness reporting is incompatible with baselines'
        end

        edges = value.cycle.map { |item| edge(item) }
        return unless edges.map(&:first).uniq.length == edges.length

        start = edges.each_index.min_by { |index| JSON.generate(edges[index]) }
        { 'cycle' => edges.rotate(start) }
      end

      def self.threshold(value)
        { 'subject' => identifier(value.identifier), 'metric' => value.metric_name.to_s,
          'value' => value.value, 'threshold' => value.threshold,
          'comparison' => value.comparison.to_s }
      end

      def self.identifier(value)
        normalized = value.tr('\\', '/')
        if normalized.start_with?('/') || normalized.match?(/\A[a-z]:/i)
          raise ArgumentError, 'baseline identities require project-relative identifiers'
        end

        normalized
      end
      private_class_method :dependency, :edge, :layer, :slice, :pattern, :named_call, :filter,
                           :cycle, :threshold, :identifier
    end
  end
end
